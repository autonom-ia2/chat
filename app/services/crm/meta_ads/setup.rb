# Conexão guiada de Anúncios da Meta (#1047): lista as contas de anúncios que a conta pode usar, lista os
# Pixels de uma conta e grava a escolha só depois de ler a conta de verdade (CA-1.2).
#
# Modo `token`: o token colado pelo cliente (já salvo na conexão) lista as contas dele.
# Modo `partner`: o token da plataforma lê as contas que clientes compartilharam com o portfólio da
# plataforma. Como esse token enxerga contas de todos os clientes, cada conta do Chat2You só vê e só escolhe
# contas cujo portfólio dono é um portfólio do seu próprio WhatsApp (Crm::MetaAds::Portfolios) e que nenhuma
# outra conta já usa. Listar não muda nada na Meta; o usuário do sistema da plataforma só é atribuído à conta
# (Ver desempenho) quando ela é escolhida.
#
# Erros voltam como códigos (`Error#code`), que a tela traduz em uma frase.
class Crm::MetaAds::Setup
  class Error < StandardError
    attr_reader :code

    def initialize(code)
      @code = code
      super(code)
    end
  end

  ACTIVE_ACCOUNT_STATUS = 1
  MAX_SPEND_LOOKUPS = 10

  def initialize(account)
    @account = account
  end

  # [{ id:, name:, currency:, active:, spend_30d:, ready:, recommended: }], a recomendada primeiro.
  def ad_accounts(mode)
    candidates = mode == 'partner' ? partner_candidates : token_candidates
    with_spend(candidates)
  end

  def pixels(mode, ad_account_id)
    client = client_for(mode)
    ensure_allowed!(mode, client, ad_account_id)
    list_pixels(client, ad_account_id)
  end

  # Lê a conta (nome, gasto dos últimos 30 dias) e o Pixel antes de gravar. Qualquer leitura que falhe
  # aborta sem mexer na conexão.
  def select!(mode:, ad_account_id:, pixel_id:)
    raise Error, 'invalid_ad_account' unless Crm::MetaAds::NameResolver.meta_id?(ad_account_id)

    client = client_for(mode)
    grant_platform_access!(client, ad_account_id) if mode == 'partner'
    details = ensure_allowed!(mode, client, ad_account_id)
    spend = client.spend_last_30d(ad_account_id)
    raise_graph!(spend) unless spend.ok

    pixel = pixel_id.present? ? find_pixel!(client, ad_account_id, pixel_id) : nil
    save!(mode, details, pixel)
  end

  def portfolio_ids
    @portfolio_ids ||= Crm::MetaAds::Portfolios.for(@account)
  end

  private

  def connection
    @connection ||= Crm::MetaAdsConnection.find_or_initialize_by(account_id: @account.id)
  end

  def client_for(mode)
    token = mode == 'partner' ? Crm::MetaAds::Platform.token : saved_token
    raise Error, (mode == 'partner' ? 'platform_unavailable' : 'token_missing') if token.blank?

    @client = Meta::AdsGraphClient.new(access_token: token)
  end

  def saved_token
    connection.access_token if connection.persisted? && connection.token_mode?
  end

  def token_candidates
    result = client_for('token').ad_accounts
    raise_graph!(result) unless result.ok

    Array(result.data.to_h['data']).map { |row| candidate(row, ready: true) }
  end

  # Contas compartilhadas pelos portfólios desta conta. `ready` diz se o usuário do sistema da plataforma já
  # foi atribuído a ela; a atribuição acontece na escolha (grant_platform_access!).
  def partner_candidates
    raise Error, 'no_portfolio' if portfolio_ids.empty?

    client = client_for('partner')
    assigned = assigned_ids(client)
    shared_accounts(client).map { |row| candidate(row, ready: assigned.include?(row_id(row))) }
  end

  # Só conta compartilhada por um portfólio desta conta e livre recebe o usuário do sistema da plataforma.
  def grant_platform_access!(client, ad_account_id)
    raise Error, 'no_portfolio' if portfolio_ids.empty?
    raise Error, 'not_shared' unless shared_accounts(client).any? { |row| row_id(row) == ad_account_id.to_s }
    return if assigned_ids(client).include?(ad_account_id.to_s)

    raise Error, 'platform_access_pending' unless assign(client, ad_account_id)
  end

  def shared_accounts(client)
    @shared_accounts ||= begin
      result = client.client_ad_accounts(Crm::MetaAds::Platform.business_id)
      raise_graph!(result) unless result.ok

      Array(result.data.to_h['data']).select { |row| owned_here?(row) && !claimed_elsewhere?(row_id(row)) }
    end
  end

  # Contas que o usuário do sistema da plataforma já enxerga. O token da plataforma é o dele, então é o
  # `me/adaccounts`. Recusa da Meta vira erro na tela, nunca lista vazia: lista vazia aqui quer dizer "ainda
  # não atribuída" e travava a escolha em silêncio (#1068).
  def assigned_ids(client)
    @assigned_ids ||= begin
      result = client.ad_accounts
      raise_graph!(result) unless result.ok

      Array(result.data.to_h['data']).map { |row| row_id(row) }
    end
  end

  def assign(client, ad_account_id)
    system_user_id = Crm::MetaAds::Platform.system_user_id
    return false if system_user_id.blank?

    client.assign_system_user(ad_account_id, system_user_id: system_user_id, business_id: Crm::MetaAds::Platform.business_id).ok
  end

  def candidate(row, ready:)
    { id: row_id(row), name: row['name'].to_s, currency: row['currency'], active: row['account_status'].to_i == ACTIVE_ACCOUNT_STATUS,
      business_name: row.dig('business', 'name'), ready: ready }
  end

  def with_spend(candidates)
    rows = candidates.each_with_index.map { |row, index| row.merge(spend_30d: lookup_spend?(row, index) ? spend_for(row[:id]) : nil) }
    recommended = rows.select { |row| row[:ready] }.max_by { |row| row[:spend_30d].to_f }
    rows.map { |row| row.merge(recommended: row.equal?(recommended)) }.sort_by { |row| recommended_first(row) }
  end

  def lookup_spend?(row, index)
    row[:ready] && index < MAX_SPEND_LOOKUPS
  end

  def recommended_first(row)
    [row[:recommended] ? 0 : 1, -row[:spend_30d].to_f]
  end

  # Gasto é só para ordenar e recomendar: sem resposta da Meta a conta aparece sem valor.
  def spend_for(ad_account_id)
    result = @client.spend_last_30d(ad_account_id)
    return unless result.ok

    Array(result.data.to_h['data']).sum { |row| row['spend'].to_f }
  end

  # A conta precisa existir para este token e, no modo `partner`, pertencer a um portfólio desta conta e
  # não estar em uso por outra conta do Chat2You.
  def ensure_allowed!(mode, client, ad_account_id)
    raise Error, 'invalid_ad_account' unless Crm::MetaAds::NameResolver.meta_id?(ad_account_id)

    result = client.ad_account(ad_account_id)
    raise_graph!(result) unless result.ok

    details = result.data.to_h
    if mode == 'partner'
      raise Error, 'not_your_portfolio' unless owned_here?(details)
      raise Error, 'ad_account_in_use' if claimed_elsewhere?(ad_account_id.to_s)
    end
    details
  end

  def list_pixels(client, ad_account_id)
    result = client.ad_account_pixels(ad_account_id)
    raise_graph!(result) unless result.ok

    Array(result.data.to_h['data']).map { |pixel| { id: pixel['id'].to_s, name: pixel['name'], last_fired_time: pixel['last_fired_time'] } }
  end

  def find_pixel!(client, ad_account_id, pixel_id)
    pixel = list_pixels(client, ad_account_id).find { |row| row[:id] == pixel_id.to_s }
    raise Error, 'pixel_not_found' if pixel.blank?

    pixel
  end

  def save!(mode, details, pixel)
    connection.assign_attributes(
      mode: mode, ad_account_id: row_id(details), ad_account_name: limited(details['name']),
      ad_account_business_id: details.dig('business', 'id')&.to_s, pixel_id: pixel&.dig(:id), pixel_name: limited(pixel&.dig(:name)),
      status: 'active', verified_at: Time.current, last_checked_at: Time.current, last_error: nil
    )
    connection.access_token = nil if mode == 'partner'
    reset_insights_on_new_ad_account
    connection.save!
    Crm::MetaAds::BackfillJob.perform_later(@account.id)
    Crm::MetaAds::InsightsBackfillJob.start(connection) if connection.insights_backfilled_at.nil?
    connection
  end

  # Outra conta de anúncios: a coleta começa do zero, com a carga de 90 dias (#1073).
  def reset_insights_on_new_ad_account
    return unless connection.ad_account_id_changed?

    connection.assign_attributes(insights_synced_at: nil, insights_backfilled_at: nil)
  end

  def limited(text)
    text.to_s.first(Crm::MetaAdsConnection::NAME_LIMIT).presence
  end

  def owned_here?(row)
    portfolio_ids.include?(row.dig('business', 'id').to_s)
  end

  def claimed_elsewhere?(ad_account_id)
    Crm::MetaAdsConnection.where(mode: 'partner', ad_account_id: ad_account_id).where.not(account_id: @account.id).exists?
  end

  # A Graph devolve `id` como "act_123" e `account_id` como "123".
  def row_id(row)
    (row['account_id'].presence || row['id'].to_s.delete_prefix('act_')).to_s
  end

  def raise_graph!(result)
    raise Error, 'meta_unavailable' if result.transient?
    raise Error, 'token_invalid' if result.token_invalid?
    raise Error, 'no_access' if result.scope_error? || result.object_error?

    raise Error, 'meta_unavailable'
  end
end
