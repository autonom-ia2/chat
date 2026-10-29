# Gestão mínima do anúncio (#2161): se ele está no ar ou pausado, pausar ou ativar a pedido da pessoa, o post da
# Página por trás dele e as Páginas da conexão. Chama a Meta ao vivo, com o token da conexão; nada aqui é gravado.
#
# - Só mexe em anúncio da conta de anúncios escolhida na conexão: a Meta devolve o `account_id` do anúncio e um
#   anúncio de outra conta responde como inexistente (`ad_not_found`), mesmo que o token o alcance.
# - Mudar a situação exige token do próprio cliente (modos `token` e `facebook_login`) com `ads_management`
#   concedida. No modo `partner` o usuário do sistema da plataforma só tem "Ver desempenho" (ANALYZE): nunca muda.
# - O post é lido com o token do cliente; se a Meta recusar por permissão, com o token da Página (o caminho que a
#   documentação dá para pages_read_engagement). Sem post, ou sem leitura, `post` vem nil: a tela some com o cartão.
#
# Erros de `change!`: `invalid_status`, `cannot_change` (modo ou permissão), `ad_not_found`, `meta_unavailable`
# (rede, 5xx, limite) e `meta_refused` (qualquer outra recusa da Meta).
#
# `in_review` (#2354): anúncio pausado que a Meta ainda analisa (`effective_status` PENDING_REVIEW ou IN_PROCESS). A doc
# do Ad não diz se dá para ligar um anúncio durante a análise: a tela não oferece o Ativar, em nenhum lugar, e o
# servidor recusa ligar (`in_review`), aqui e no anúncio criado pelo Chat2You (Crm::MetaAds::Creation::Activation).
class Crm::MetaAds::AdManagement
  class Error < StandardError
    attr_reader :code

    def initialize(code)
      @code = code
      super(code)
    end
  end

  STATUSES = %w[ACTIVE PAUSED].freeze
  IN_REVIEW = %w[PENDING_REVIEW IN_PROCESS].freeze
  ADS_MANAGEMENT = 'ads_management'.freeze

  def self.in_review?(status, effective_status)
    status == 'PAUSED' && IN_REVIEW.include?(effective_status)
  end

  def initialize(connection)
    @connection = connection
  end

  def payload(ad_id)
    ad = read_ad(ad_id)
    return if ad.nil?

    {
      name: ad['name'], status: ad['status'], effective_status: ad['effective_status'],
      in_review: self.class.in_review?(ad['status'], ad['effective_status']), mode: @connection.mode,
      can_change: can_change?, needs_login: @connection.own_token? && !ads_management?,
      post: post_payload(ad.dig('creative', 'effective_object_story_id'))
    }
  end

  def change!(ad_id, status)
    raise Error, 'invalid_status' unless STATUSES.include?(status)
    raise Error, 'ad_not_found' unless numeric_id?(ad_id)
    raise Error, 'cannot_change' unless can_change?

    ensure_switchable!(read_ad(ad_id), status)
    result = client.update_ad_status(ad_id, status)
    return status if result.ok

    raise Error, result.transient? ? 'meta_unavailable' : 'meta_refused'
  end

  # O anúncio como a Meta devolve (com o criativo), só se for da conta de anúncios da conexão; senão nil.
  def ad(ad_id)
    read_ad(ad_id)
  end

  # Nome do anúncio pelo cache de nomes (para a Auditoria); nil se ainda não foi lido.
  def ad_name(ad_id)
    Crm::MetaAdObject.where(account_id: @connection.account_id, meta_object_id: ad_id.to_s).pick(:name)
  end

  # Só com o token do próprio cliente: no modo `partner` o token é o da plataforma, e `me/accounts` traria Páginas
  # da plataforma (ou de outros clientes) para esta conta.
  def pages
    return [] unless @connection.own_token?

    result = client.pages
    return [] unless result.ok

    Array(result.data['data']).filter_map { |page| { id: page['id'], name: page['name'] } if page.is_a?(Hash) && page['name'].present? }
  end

  private

  def client
    @client ||= Meta::AdsGraphClient.new(access_token: @connection.read_token)
  end

  def can_change?
    @connection.own_token? && ads_management?
  end

  def ads_management?
    return @ads_management if defined?(@ads_management)

    result = client.permissions
    @ads_management = result.ok && Array(result.data.to_h['data']).any? do |entry|
      entry.is_a?(Hash) && entry['permission'] == ADS_MANAGEMENT && entry['status'] == Meta::AdsGraphClient::GRANTED
    end
  end

  # O anúncio só vale se for da conta de anúncios da conexão e se a Meta devolver o mesmo id. Recusa por objeto, por
  # permissão ou de outra conta: nil. Falha passageira vira `meta_unavailable`, para a tela dizer "tente de novo" em
  # vez de sumir com o anúncio.
  def ensure_switchable!(meta_ad, status)
    raise Error, 'ad_not_found' if meta_ad.nil?
    raise Error, 'in_review' if status == 'ACTIVE' && self.class.in_review?(meta_ad['status'], meta_ad['effective_status'])
  end

  def read_ad(ad_id)
    return unless numeric_id?(ad_id)

    @ads ||= {}
    return @ads[ad_id] if @ads.key?(ad_id)

    result = client.ad_management(ad_id)
    raise Error, 'meta_unavailable' if result.transient?

    @ads[ad_id] = own_ad?(result, ad_id) ? result.data : nil
  end

  # O id entra no caminho da Graph: só dígitos, para que `?`, `/` ou `&` (o Rails decodifica %3F, %2F…) não virem
  # outro caminho ou parâmetros extras na chamada à Meta.
  def numeric_id?(ad_id)
    ad_id.is_a?(String) && ad_id.present? && ad_id.each_char.all? { |char| char.between?('0', '9') }
  end

  def own_ad?(result, ad_id)
    result.ok && result.data['id'].to_s == ad_id && result.data['account_id'].to_s == @connection.ad_account_id.to_s
  end

  def post_payload(post_id)
    return if post_id.blank?

    data = read_post(post_id)
    return if data.nil?

    {
      message: data['message'], created_time: data['created_time'], permalink_url: data['permalink_url'],
      page_name: data.dig('from', 'name'), reactions: data.dig('reactions', 'summary', 'total_count').to_i,
      comments: data.dig('comments', 'summary', 'total_count').to_i, shares: data.dig('shares', 'count').to_i
    }
  end

  # Ler post de Página com token de usuário costuma voltar por permissão (10, 200–299) ou como "não pode ser lido"
  # (100): nos dois casos, segunda tentativa com o token da Página.
  def read_post(post_id)
    result = client.page_post(post_id)
    return result.data if result.ok
    return unless result.scope_error? || result.object_error?

    page_token = client.page_access_token(post_id.to_s.split('_').first)
    token = page_token.data.to_h['access_token'] if page_token.ok
    return if token.blank?

    retry_result = Meta::AdsGraphClient.new(access_token: token).page_post(post_id)
    retry_result.data if retry_result.ok
  end
end
