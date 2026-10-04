require 'ipaddr'

class Instagram::Testers::Proxy
  def initialize
    @host = ENV.fetch('INSTAGRAM_TESTER_PROXY_HOST', '')
    @port = ENV.fetch('INSTAGRAM_TESTER_PROXY_PORT', '')
    @auth_mode = ENV.fetch('INSTAGRAM_TESTER_PROXY_AUTH_MODE', '')
    @identity = ENV.fetch('INSTAGRAM_TESTER_PROXY_IDENTITY', nil)
    @username = ENV.fetch('INSTAGRAM_TESTER_PROXY_USERNAME', '')
    @password = ENV.fetch('INSTAGRAM_TESTER_PROXY_PASSWORD', '')
  end

  def configured?
    [@host, @port, @auth_mode, @identity, @username, @password].any?(&:present?)
  end

  def valid?
    valid_host? && valid_port? && valid_identity? && @auth_mode == 'ip' && @username.empty? && @password.empty?
  end

  def fingerprint
    raise Instagram::Testers::Error, 'proxy_unavailable' unless valid?

    endpoint = @identity || "#{@host}:#{@port.to_i}"
    Digest::SHA256.hexdigest("#{endpoint}:#{@auth_mode}")
  end

  def transport_options
    raise Instagram::Testers::Error, 'proxy_unavailable' unless valid?

    { http_proxyaddr: @host, http_proxyport: @port.to_i, http_proxyuser: nil, http_proxypass: nil, max_retries: 0 }
  end

  def upstream_host
    raise Instagram::Testers::Error, 'proxy_unavailable' unless valid?

    @identity ? @identity.split(':').first : @host
  end

  private

  def valid_host?
    return true if @host == 'ig-proxy.internal'

    address = IPAddr.new(@host)
    address.ipv4? && address.to_s == @host
  rescue IPAddr::InvalidAddressError
    false
  end

  def valid_port?
    Instagram::Testers::Validation.id?(@port) && @port.to_i.between?(1, 65_535)
  end

  def valid_identity?
    local = @host == 'ig-proxy.internal' || IPAddr.new(@host).loopback?
    return !local if @identity.nil?

    canonical_upstream? && (local || @identity == "#{@host}:#{@port.to_i}")
  rescue IPAddr::InvalidAddressError, TypeError
    false
  end

  def canonical_upstream?
    parts = @identity.split(':', -1)
    return false unless parts.length == 2

    host, port = parts
    return false unless canonical_upstream_port?(port)

    address = IPAddr.new(host)
    address.ipv4? && address.to_s == host && !address.loopback?
  end

  def canonical_upstream_port?(port)
    Instagram::Testers::Validation.id?(port) && port.to_i.between?(1, 65_535) && port.to_i.to_s == port
  end
end
