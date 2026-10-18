# Cliente da Graph API para os modelos de mensagem do WhatsApp oficial (Cloud) de UMA caixa (#1330, épico #1320).
# Herdou o molde do antigo criador dos avisos v1 do agendamento (#1280, retirado em #1612): não duplica pelo nome, tenta de novo quando a Meta
# está fora do ar ou pede calma (5xx/429), reconhece falta de permissão pelo código numérico da Meta e nunca devolve o
# token no texto do erro.
#
# Isolamento entre clientes: a conta do WhatsApp (WABA) é SEMPRE a gravada na caixa (`channel.waba_id`) e o token é o
# da caixa (`template_access_token`). Nada daqui aceita WABA de fora. O mesmo token pode alcançar WABAs de outras contas
# (em produção, um token serve caixas de 4 contas), por isso editar, apagar ou consultar por id só acontece depois de
# confirmar, pela lista da WABA da caixa, que o id é dela.
class Whatsapp::Templates::MetaClient
  include Whatsapp::Templates::GraphErrors

  class Unsupported < StandardError; end
  # A Meta não respondeu (rede, prazo) ou seguiu fora do ar depois das tentativas.
  class Unreachable < StandardError; end
  # O modelo não está na WABA da caixa.
  class NotFound < StandardError; end

  # A Meta recusou. `own_text`: `message` é texto nosso; sem ele, `message` é o texto da Meta (sem o token), que não vai
  # para a tela (#1394). `code`: o código nosso (`name_taken`, `permission_denied`…) ou `meta_text` quando não há um.
  class MetaError < StandardError
    attr_reader :own_text, :code

    def initialize(message, own_text: false, code: nil)
      super(message)
      @own_text = own_text
      @code = code || (own_text ? nil : 'meta_text')
    end
  end

  # `created`: falso quando o nome e o idioma já existiam na WABA (nada foi criado de novo).
  Outcome = Data.define(:template, :created)

  DEFAULT_API_VERSION = 'v22.0'.freeze
  REQUEST_TIMEOUT = 10
  UPLOAD_TIMEOUT = 60
  CREATE_KEYS = %w[name language category components parameter_format message_send_ttl_seconds].freeze
  # A categoria não vai na edição: a Meta recusa a troca (#1394) e o `Manager` já barra antes.
  EDIT_KEYS = %w[components message_send_ttl_seconds].freeze
  COMPONENT_KEYS = %w[type format text example buttons cards limited_time_offer add_security_recommendation
                      code_expiration_minutes].freeze
  # Tipos que a Resumable Upload API aceita para o exemplo do topo, com o teto de tamanho de cada um.
  MEDIA_LIMITS = { 'image/jpeg' => 5.megabytes, 'image/png' => 5.megabytes, 'video/mp4' => 16.megabytes,
                   'application/pdf' => 100.megabytes }.freeze

  def self.supported?(inbox)
    channel = inbox&.channel
    channel.is_a?(Channel::Whatsapp) && channel.provider == 'whatsapp_cloud' && channel.waba_id.present?
  end

  def self.api_version
    GlobalConfigService.load('WHATSAPP_API_VERSION', DEFAULT_API_VERSION).presence || DEFAULT_API_VERSION
  end

  def initialize(inbox:)
    raise Unsupported unless self.class.supported?(inbox)

    @inbox = inbox
  end

  # Cria o modelo na WABA da caixa. Se o nome já existe no mesmo idioma (outra tela, outra pessoa), devolve o que existe
  # com `created: false`. Se aparece depois de um envio deste pedido que a rede cortou, foi este pedido que criou.
  def create(body)
    body = create_body(body)
    posted = false
    with_retry do
      existing = lookup(body['name']).find { |item| same_template?(item, body) }
      next Outcome.new(template: existing, created: posted) if existing

      posted = true
      response = HTTParty.post(templates_url, headers: bearer_headers, body: body.to_json, timeout: REQUEST_TIMEOUT)
      next Outcome.new(template: created(body, response), created: true) if response.success?

      retry_later!(response)
      existing = lookup(body['name']).find { |item| same_template?(item, body) }
      existing ? Outcome.new(template: existing, created: false) : fail_with(response)
    end
  end

  # Edita componentes ou validade (a Meta não deixa mudar nome nem idioma; a categoria o produto não muda, #1394). Volta para análise na Meta.
  def update(template_id, name, body)
    ensure_owned!(template_id, name)
    body = body.to_h.deep_stringify_keys.slice(*EDIT_KEYS)
    body['components'] = sanitize_components(body['components']) if body.key?('components')
    with_retry do
      response = HTTParty.post(graph_url(template_id.to_s), headers: bearer_headers, body: body.to_json, timeout: REQUEST_TIMEOUT)
      next true if response.success?

      retry_later!(response)
      fail_with(response)
    end
  end

  # Apaga só aquele modelo (um idioma). A Meta exige o nome junto com o id.
  def delete_by_id(template_id, name)
    ensure_owned!(template_id, name)
    delete(name: name, hsm_id: template_id.to_s)
  end

  # Apaga o nome em TODOS os idiomas da WABA da caixa.
  def delete_by_name(name)
    delete(name: name.to_s)
  end

  # Um modelo da WABA da caixa, com status, categoria, categoria correta, qualidade e motivo de recusa.
  def find(template_id, name)
    by_name(name).find { |item| item['id'].to_s == template_id.to_s } || raise(NotFound)
  end

  def find_by_name(name, language)
    by_name(name).find { |item| item['name'] == name.to_s && item['language'].to_s.casecmp?(language.to_s) }
  end

  # Sobe o arquivo de exemplo do topo pela Resumable Upload API e devolve o handle (`header_handle`) que vai no modelo.
  def upload_media(io:, file_name:, content_type:)
    check_media!(content_type, io.size.to_i)
    content = io.read.to_s
    check_media!(content_type, content.bytesize)
    session = open_upload_session(file_name, content_type, content.bytesize)
    with_retry do
      response = HTTParty.post(graph_url(session), headers: oauth_headers.merge('file_offset' => '0'), body: content,
                                                   timeout: UPLOAD_TIMEOUT)
      next payload(response)['h'].presence || fail_with(response) if response.success?

      retry_later!(response)
      fail_with(response)
    end
  end

  private

  def channel
    @inbox.channel
  end

  def account
    @inbox.account
  end

  def create_body(body)
    body = body.to_h.deep_stringify_keys.slice(*CREATE_KEYS)
    body['components'] = sanitize_components(body['components'])
    body
  end

  def sanitize_components(components)
    Array(components).map { |component| component.to_h.deep_stringify_keys.slice(*COMPONENT_KEYS) }
  end

  def created(body, response)
    { 'id' => payload(response)['id'].to_s, 'name' => body['name'], 'language' => body['language'],
      'status' => payload(response)['status'].presence || 'PENDING',
      'category' => payload(response)['category'].presence || body['category'], 'components' => body['components'],
      'parameter_format' => body['parameter_format'] }.compact
  end

  def same_template?(item, body)
    item['name'] == body['name'] && item['language'].to_s.casecmp?(body['language'].to_s)
  end

  def by_name(name)
    with_retry { lookup(name) }
  end

  # Uma consulta à WABA da caixa pelo nome, sem repetir (quem chama decide a repetição).
  def lookup(name)
    response = HTTParty.get(templates_url, query: { name: name.to_s, fields: Whatsapp::Templates::SyncFields::FIELDS, limit: 100 },
                                           headers: bearer_headers, timeout: REQUEST_TIMEOUT)
    return Array(payload(response)['data']).select { |item| item.is_a?(Hash) } if response.success?

    retry_later!(response)
    fail_with(response)
  end

  def ensure_owned!(template_id, name)
    find(template_id, name)
  end

  # Numa nova tentativa, o que já não está na WABA foi apagado pela tentativa que a rede cortou.
  def delete(query)
    tried = false
    with_retry do
      next true if tried && gone?(query)

      tried = true
      response = HTTParty.delete(templates_url, query: query, headers: bearer_headers, timeout: REQUEST_TIMEOUT)
      next true if response.success?

      retry_later!(response)
      fail_with(response)
    end
  end

  def gone?(query)
    remaining = lookup(query[:name]).select { |item| item['name'] == query[:name] }
    query[:hsm_id] ? remaining.none? { |item| item['id'].to_s == query[:hsm_id] } : remaining.empty?
  end

  def check_media!(content_type, size)
    limit = MEDIA_LIMITS[content_type.to_s]
    return if limit && size.positive? && size <= limit

    raise MetaError.new(text('media_invalid'), own_text: true, code: 'media_invalid')
  end

  def open_upload_session(file_name, content_type, size)
    app_id = GlobalConfigService.load('WHATSAPP_APP_ID', '').to_s
    raise MetaError.new(text('app_not_configured'), own_text: true, code: 'app_not_configured') if app_id.blank?

    with_retry do
      response = HTTParty.post(graph_url("#{app_id}/uploads"), headers: oauth_headers, timeout: REQUEST_TIMEOUT,
                                                               query: { file_name: file_name.to_s, file_length: size, file_type: content_type })
      next payload(response)['id'].presence || fail_with(response) if response.success?

      retry_later!(response)
      fail_with(response)
    end
  end

  def templates_url
    graph_url("#{channel.waba_id}/message_templates")
  end

  def graph_url(path)
    "#{ENV.fetch('WHATSAPP_CLOUD_BASE_URL', 'https://graph.facebook.com')}/#{self.class.api_version}/#{path}"
  end

  def bearer_headers
    { 'Authorization' => "Bearer #{channel.template_access_token}", 'Content-Type' => 'application/json' }
  end

  # A Resumable Upload API pede `OAuth`, não `Bearer`.
  def oauth_headers
    { 'Authorization' => "OAuth #{channel.template_access_token}" }
  end
end
