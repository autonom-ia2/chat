# Quem preencheu um formulário nos últimos 90 dias (#2195): quantos são, para a tela, e trazer para o funil escolhido.
# Lê com o token da Página (leads_retrieval), tirado na hora do token do cliente e nunca guardado.
#
# As duas leituras rodam em segundo plano (CountPastJob e ImportPastJob), página a página até o fim: a tela só lê o
# número que ficou guardado, e um formulário com milhares de leads não segura a resposta nem gasta o limite de uso a
# cada abertura. A Meta não documenta contagem resumida no /{form}/leads, então contar é paginar.
class Crm::MetaAds::LeadForms::PastLeads
  WINDOW = 90.days
  COUNT_TTL = 15.minutes
  # A trava da contagem sai no fim do CountPastJob (ensure); o prazo só vale se o processo morrer no meio. Maior que
  # 500 páginas lidas no pior caso, para não pedir uma segunda contagem com a primeira ainda rodando.
  COUNTING_TTL = 2.hours

  # Monta a leitura com o token da Página tirado da conexão da conta. nil quando a conta não tem conexão com token
  # próprio. Recusa da Meta sobe como Error; queda, como Unavailable.
  def self.for(account:, page_id:, form_id:, form_name:)
    connection = Crm::MetaAdsConnection.active.find_by(account_id: account.id)
    return unless connection&.own_token?

    result = Meta::AdsGraphClient.new(access_token: connection.read_token).page_access_token(page_id)
    check!(result)
    token = result.data.to_h['access_token']
    raise Crm::MetaAds::LeadForms::Error, 'meta_refused' if token.blank?

    new(account: account, page: { 'id' => page_id.to_s, 'access_token' => token }, form: { 'id' => form_id.to_s, 'name' => form_name })
  end

  def self.check!(result)
    return if result.ok
    raise Crm::MetaAds::LeadForms::Unavailable if result.transient?

    raise Crm::MetaAds::LeadForms::Error, 'meta_refused'
  end

  # { count:, truncated: } que ficou guardado; sem ele, pede a contagem em segundo plano (uma por vez) e a tela mostra
  # sem número. truncated: a leitura parou no teto, e o número é "N ou mais".
  def self.cached_count(account:, page_id:, form_id:)
    cached = Rails.cache.read(cache_key(account.id, form_id))
    return cached.symbolize_keys if cached.is_a?(Hash)

    if Rails.cache.write(counting_key(account.id, form_id), true, expires_in: COUNTING_TTL, unless_exist: true)
      Crm::MetaAds::LeadForms::CountPastJob.perform_later(account.id, page_id.to_s, form_id.to_s)
    end
    nil
  end

  def self.cache_key(account_id, form_id)
    ['crm_meta_ads_lead_forms', 'past_count', account_id, form_id.to_s]
  end

  def self.counting_key(account_id, form_id)
    [*cache_key(account_id, form_id), 'counting']
  end

  def initialize(account:, page:, form:)
    @account = account
    @page = page
    @form = form
  end

  def count!
    rows, truncated = read
    counted = { 'count' => rows.size, 'truncated' => truncated }
    Rails.cache.write(self.class.cache_key(@account.id, @form['id']), counted, expires_in: COUNT_TTL)
    counted.symbolize_keys
  end

  # Quantos viraram card novo (os repetidos e quem já tinha card aberto no funil não contam).
  def import!(pipeline:, stage:)
    questions = client.lead_form_questions(@form['id'])
    importer = Crm::MetaAds::LeadForms::Importer.new(
      account: @account, pipeline: pipeline, stage: stage, form_name: @form['name'], page_id: @page['id'],
      questions: questions.ok ? Array(questions.data.to_h['questions']) : []
    )
    rows, truncated = read
    imported = rows.count { |lead| importer.import(lead) == :created }
    Rails.cache.delete(self.class.cache_key(@account.id, @form['id']))
    { imported: imported, truncated: truncated }
  end

  private

  def client
    @client ||= Meta::AdsGraphClient.new(access_token: @page['access_token'])
  end

  def read
    list = []
    result, truncated = client.each_form_lead(@form['id'], since: WINDOW.ago) { |batch| list.concat(batch) }
    self.class.check!(result)
    [list.select { |lead| lead.is_a?(Hash) && lead['id'].present? }, truncated]
  end
end
