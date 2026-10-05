class Instagram::Automation::OperatorBrowserTicket
  STACKS = %w[hub2you autonomia].freeze
  ACTIVE_STATES = %w[queued running operator_required].freeze
  TICKET_TTL = 60

  class Unavailable < StandardError
    def initialize
      super('operator_browser_unavailable')
    end
  end

  def self.eligible?(control:, actor_id:)
    ENV.fetch('INSTAGRAM_TESTER_SESSION_SOURCE', 'env') == 'managed' && control.present? &&
      ACTIVE_STATES.include?(control['state']) && control['actor_id'] == actor_id &&
      Time.iso8601(control.fetch('created_at')) + Instagram::Automation::OperatorControl::REQUEST_TTL > Time.current
  end

  def self.configured?
    new
    true
  rescue Unavailable
    false
  end

  def initialize
    @stack = ENV.fetch('INSTAGRAM_TESTER_RUNTIME_STACK', '')
    raise Unavailable unless STACKS.include?(@stack)

    @url = https_url(ENV.fetch('INSTAGRAM_TESTER_OPERATOR_BROWSER_URL', ''))
    raise Unavailable unless @url.path == "/#{@stack}/"

    @issuer = https_url(ENV.fetch('FRONTEND_URL', '')).origin
    @key = signing_key
  end

  def call(control:, actor_id:)
    raise Unavailable unless self.class.eligible?(control: control, actor_id: actor_id)

    now = Time.current.to_i
    claims = {
      iss: @issuer, aud: "instagram-operator-browser:#{@stack}", sub: actor_id.to_s,
      jti: SecureRandom.uuid, iat: now, exp: now + TICKET_TTL, request_id: control.fetch('id'),
      deadline: (Time.iso8601(control.fetch('created_at')) + Instagram::Automation::OperatorControl::REQUEST_TTL).to_i, stack: @stack
    }
    { ticket: JWT.encode(claims, @key, 'HS256', typ: 'JWT'), grant_url: "#{@url}grant" }
  end

  private

  def https_url(value)
    uri = URI.parse(value)
    raise Unavailable unless uri.is_a?(URI::HTTPS) && uri.host.present? && uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil?

    uri
  rescue URI::InvalidURIError
    raise Unavailable, cause: nil
  end

  def signing_key
    hex = ENV.fetch('INSTAGRAM_TESTER_OPERATOR_BROWSER_SIGNING_KEY', '')
    raise Unavailable unless hex.size >= 64 && hex.size.even? && hex.each_char.all? { |char| '0123456789abcdefABCDEF'.include?(char) }

    [hex].pack('H*')
  end
end
