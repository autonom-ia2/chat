require 'ipaddr'

class Instagram::Testers::Proxy
  def initialize
    @host = ENV.fetch('INSTAGRAM_TESTER_PROXY_HOST', '')
    @port = ENV.fetch('INSTAGRAM_TESTER_PROXY_PORT', '')
    @auth_mode = ENV.fetch('INSTAGRAM_TESTER_PROXY_AUTH_MODE', '')
    @username = ENV.fetch('INSTAGRAM_TESTER_PROXY_USERNAME', '')
    @password = ENV.fetch('INSTAGRAM_TESTER_PROXY_PASSWORD', '')
  end

  def configured?
    [@host, @port, @auth_mode, @username, @password].any?(&:present?)
  end

  def valid?
    valid_host? && valid_port? && @auth_mode == 'ip' && @username.empty? && @password.empty?
  end

  def fingerprint
    raise Instagram::Testers::Error, 'proxy_unavailable' unless valid?

    Digest::SHA256.hexdigest([@host.downcase, @port.to_i, @auth_mode].join(':'))
  end

  def transport_options
    raise Instagram::Testers::Error, 'proxy_unavailable' unless valid?

    { http_proxyaddr: @host, http_proxyport: @port.to_i, http_proxyuser: nil, http_proxypass: nil, max_retries: 0 }
  end

  private

  def valid_host?
    address = IPAddr.new(@host)
    address.ipv4? && address.to_s == @host
  rescue IPAddr::InvalidAddressError
    false
  end

  def valid_port?
    Instagram::Testers::Validation.id?(@port) && @port.to_i.between?(1, 65_535)
  end
end
