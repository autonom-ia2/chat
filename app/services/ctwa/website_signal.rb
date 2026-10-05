# Lê o aviso de clique que uma página manda (POST /l/:code/clicks, #1011) e devolve só o
# que pode ser gravado. Entrada externa e anônima: tudo é limitado em tamanho, campo
# estranho some, e campo inválido é descartado em silêncio — o clique em si ainda vale.
# Nada aqui usa expressão regular: formato é conferido com métodos de string e URI.
class Ctwa::WebsiteSignal
  TOKEN_LENGTH = 8
  MAX_PARAM_LENGTH = 512
  MAX_PAGE_URL_LENGTH = 512
  MAX_META_COOKIE_LENGTH = 300
  MAX_USER_AGENT_LENGTH = 255
  MAX_LEAD_FIELDS = 12
  MAX_LEAD_KEY_LENGTH = 40
  MAX_LEAD_LABEL_LENGTH = 60
  MAX_LEAD_VALUE_LENGTH = 200
  META_COOKIE_PARTS = 4
  META_COOKIE_PREFIX = 'fb'.freeze
  DIGITS = ('0'..'9').to_a.freeze

  attr_reader :token

  def self.valid_token?(token)
    token.is_a?(String) && token.size == TOKEN_LENGTH && token.each_char.all? { |char| Ctwa::TrackedLink::CODE_ALPHABET.include?(char) }
  end

  # body: Hash já vindo do JSON. origin: origem normalizada do header (já autorizada).
  def initialize(body:, origin:, remote_ip:, user_agent:)
    @body = body.is_a?(Hash) ? body : {}
    @origin = origin
    @remote_ip = remote_ip
    @user_agent = user_agent
    @token = @body['token']
  end

  def valid_token?
    self.class.valid_token?(token)
  end

  def consent?
    @body['consent'] == true
  end

  def click_attributes
    tracking = tracking_params
    signals = meta_signals
    {
      token: token,
      params: tracking,
      campaign_key: Ctwa::TrackedLinkClick.campaign_key_for(tracking),
      page_url: page_url,
      lead_data: lead_data,
      meta_signals: signals,
      user_agent: signals['client_user_agent']
    }
  end

  private

  def tracking_params
    raw = @body['params']
    return {} unless raw.is_a?(Hash)

    raw.slice(*Ctwa::TrackedLinkClick::TRACKING_PARAM_KEYS).each_with_object({}) do |(key, value), tracking|
      next unless value.is_a?(String)

      stripped = value.strip
      tracking[key] = stripped.first(MAX_PARAM_LENGTH) if stripped.present?
    end
  end

  # Sinais da Meta só com consentimento de marketing (LGPD). Sem ele, nem o IP vai.
  def meta_signals
    return {} unless consent?

    {
      'fbc' => meta_cookie(@body['fbc']),
      'fbp' => meta_cookie(@body['fbp']),
      'client_ip_address' => @remote_ip.presence,
      'client_user_agent' => @user_agent.to_s.first(MAX_USER_AGENT_LENGTH).presence
    }.compact
  end

  # fb.<subdomínio>.<timestamp>.<valor>: quatro partes, a primeira `fb`, a terceira só dígitos.
  def meta_cookie(value)
    return unless value.is_a?(String) && value.size.between?(1, MAX_META_COOKIE_LENGTH)

    value if meta_cookie_parts?(value.split('.', META_COOKIE_PARTS))
  end

  def meta_cookie_parts?(parts)
    return false unless parts.size == META_COOKIE_PARTS && parts.all?(&:present?)

    parts.first == META_COOKIE_PREFIX && parts[2].each_char.all? { |char| DIGITS.include?(char) }
  end

  def lead_data
    fields = @body['lead'].is_a?(Hash) ? @body['lead']['fields'] : nil
    return {} unless fields.is_a?(Array)

    valid = fields.filter_map { |field| lead_field(field) }.first(MAX_LEAD_FIELDS)
    valid.any? ? { 'fields' => valid } : {}
  end

  def lead_field(field)
    return unless field.is_a?(Hash)

    key, label, value = field.values_at('key', 'label', 'value')
    return unless lead_field_fits?(key, label, value)

    { 'key' => key.strip, 'label' => label.strip, 'value' => value.strip }
  end

  def lead_field_fits?(key, label, value)
    return false unless [key, label, value].all?(String)
    return false if key.strip.empty? || value.strip.empty?

    key.size <= MAX_LEAD_KEY_LENGTH && label.size <= MAX_LEAD_LABEL_LENGTH && value.size <= MAX_LEAD_VALUE_LENGTH
  end

  # Só scheme://host/path da mesma origem que avisou; query e fragmento são cortados.
  def page_url
    uri = page_uri
    return unless uri && same_origin?(uri)

    url = "#{@origin}#{uri.path.presence || '/'}"
    url if url.size <= MAX_PAGE_URL_LENGTH
  end

  def page_uri
    raw = @body['page_url']
    return unless raw.is_a?(String)

    uri = URI.parse(raw.strip)
    uri if uri.userinfo.blank? && uri.host.present?
  rescue URI::Error
    nil
  end

  def same_origin?(uri)
    Ctwa::TrackedLink.normalize_origin("#{uri.scheme}://#{uri.host}:#{uri.port}") == @origin
  end
end
