# Cria na Meta o modelo pronto de UM aviso (#1272), na conta do WhatsApp oficial (Cloud) da caixa. Mesmo caminho do
# `Whatsapp::CsatTemplateService` (Graph API, `message_templates` da conta de negócios, categoria utility). Quem chama é o
# `NoticeTemplatesJob`, enfileirado pelo clique de um administrador; nunca roda sozinho.
#
# Não duplica: modelo da plataforma que já está na lista da caixa não é criado de novo; antes de criar, e de novo quando a
# Meta recusa, pergunta à Meta pelo nome: se já existe lá (outra página, outra pessoa, uma tentativa anterior que a rede
# cortou), só passa a constar na caixa. Por isso o job pode repetir com segurança.
#
# A sincronia da caixa (`WhatsappCloudService#sync_templates`) regrava a lista inteira com o que a Meta devolve, que já
# inclui o modelo criado.
class Crm::BookingV2::NoticeTemplates::Creator
  class Unsupported < StandardError; end
  # A Meta não respondeu (rede, prazo): o job tenta de novo.
  class Unreachable < StandardError; end

  # A Meta recusou: `message` é o texto para quem usa. `own_text`: o texto é nosso (sem permissão), não o da Meta.
  class MetaError < StandardError
    attr_reader :own_text

    def initialize(message, own_text: false)
      super(message)
      @own_text = own_text
    end
  end

  Catalog = Crm::BookingV2::NoticeTemplates::Catalog
  REQUEST_TIMEOUT = 10
  API_VERSION = Whatsapp::CsatTemplateService::WHATSAPP_API_VERSION
  MAX_ERROR = 300
  META_FIELDS = 'id,name,status,language,category,components,rejected_reason'.freeze
  PERMISSION_CODES = [10, 190].freeze
  PERMISSION_RANGE = (200..299)
  NETWORK_ERRORS = (Crm::Ai::ResponsesClient::NETWORK_ERRORS + [HTTParty::Error]).freeze

  def self.supported?(inbox)
    channel = inbox&.channel
    channel.is_a?(Channel::Whatsapp) && channel.provider == 'whatsapp_cloud' && channel.provider_config.to_h['business_account_id'].present?
  end

  def initialize(inbox:)
    @inbox = inbox
  end

  def create(kind)
    raise Unsupported unless self.class.supported?(@inbox)

    channel.reload
    return if Catalog.listed(channel.inbox, kind)

    record(existing_on_meta(kind) || create_on_meta(kind))
  rescue *NETWORK_ERRORS => e
    Rails.logger.warn("[crm][booking_v2][notice_templates] meta_unreachable inbox_id=#{@inbox.id} error=#{e.class}")
    raise Unreachable, e.class.name
  end

  private

  def channel
    @inbox.channel
  end

  def existing_on_meta(kind)
    response = HTTParty.get(templates_url, query: { name: Catalog.name_for(kind), fields: META_FIELDS }, headers: headers, timeout: REQUEST_TIMEOUT)
    return unless response.success?

    Array(payload(response)['data']).find do |item|
      item['name'] == Catalog.name_for(kind) && item['language'].to_s.casecmp?(Catalog::LANGUAGE)
    end
  end

  def create_on_meta(kind)
    body = request_body(kind)
    response = HTTParty.post(templates_url, headers: headers, body: body.to_json, timeout: REQUEST_TIMEOUT)
    return created(body, response) if response.success?
    # Meta com problema ou pedindo calma (5xx, 429): não é recusa, o job tenta de novo. Pelo código HTTP, não pelo texto.
    raise Unreachable, "http_#{response.code}" if response.code.to_i >= 500 || response.code.to_i == 429

    # Recusa por nome já usado (criado numa tentativa que a rede cortou, por exemplo): o que existe lá conta como criado.
    existing_on_meta(kind) || fail_with(response)
  end

  def created(body, response)
    { 'id' => payload(response)['id'], 'name' => body[:name], 'language' => body[:language],
      'status' => payload(response)['status'].presence || 'PENDING', 'category' => body[:category],
      'components' => body[:components].map(&:deep_stringify_keys) }
  end

  def request_body(kind)
    {
      name: Catalog.name_for(kind), language: Catalog::LANGUAGE, category: Catalog::CATEGORY,
      components: [{ type: 'BODY', text: Catalog.body_for(kind),
                     example: { body_text: [[Catalog::EXAMPLE_NAME, Catalog::EXAMPLE_WHEN, Catalog.example_link]] } }]
    }
  end

  # Põe o modelo na lista da caixa até a próxima sincronia trazer a lista da Meta (que já o inclui). Com trava e só a
  # entrada deste modelo (#1382), para não apagar o que o sync ou a tela de Modelos gravaram no meio.
  def record(template)
    Whatsapp::Templates::ChannelList.upsert!(channel, template)
    template
  end

  def fail_with(response)
    error = meta_error(response)
    raise MetaError.new(Catalog.text(@inbox.account, 'permission_denied'), own_text: true) if permission_error?(error)

    message = error['error_user_msg'].presence || error['message'].presence
    raise MetaError.new(Catalog.text(@inbox.account, 'meta_failed'), own_text: true) if message.blank?

    raise MetaError, without_token(message.to_s).first(MAX_ERROR)
  end

  # O erro da Graph API; no log só números (nada do texto, nada do token).
  def meta_error(response)
    error = payload(response)['error'].is_a?(Hash) ? payload(response)['error'] : {}
    Rails.logger.warn("[crm][booking_v2][notice_templates] meta_refused inbox_id=#{@inbox.id} http=#{response.code} " \
                      "code=#{error['code']} subcode=#{error['error_subcode']}")
    error
  end

  # O corpo da resposta, quando é um objeto JSON (a Meta fora do ar pode devolver HTML).
  def payload(response)
    response.parsed_response.is_a?(Hash) ? response.parsed_response : {}
  end

  # Erro de permissão da Graph API pelo código (10, 200–299) ou token inválido (190): a conexão da caixa não deixa criar
  # modelo. Decidido pelo número que a Meta devolve, nunca pela leitura do texto.
  def permission_error?(error)
    code = error['code'].to_i
    PERMISSION_CODES.include?(code) || PERMISSION_RANGE.cover?(code)
  end

  # O texto da Meta vai para a tela: o token nunca vai junto, nem se ela o repetir.
  def without_token(text)
    token = channel.template_access_token.to_s
    token.empty? ? text : text.gsub(token, '[token]')
  end

  def templates_url
    "#{ENV.fetch('WHATSAPP_CLOUD_BASE_URL', 'https://graph.facebook.com')}/#{API_VERSION}/#{channel.provider_config['business_account_id']}/message_templates"
  end

  def headers
    { 'Authorization' => "Bearer #{channel.template_access_token}", 'Content-Type' => 'application/json' }
  end
end
