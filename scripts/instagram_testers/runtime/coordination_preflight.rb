# Rails runner only: never invoke Meta or print transport exceptions/credentials.
begin
  coordination = Instagram::Testers::CoordinationRedis
  # with verifies integrity:epoch on this same connection before yielding.
  coordination.with { |redis| raise 'coordination_ping_failed' unless redis.ping == 'PONG' }
  proxy = Instagram::Testers::Proxy.new
  raise 'proxy_configuration_invalid' unless proxy.valid?

  response = HTTParty.get('https://ipv4.webshare.io/', **proxy.transport_options,
                         timeout: 10, follow_redirects: false)
  body = response.body.to_s.strip
  address = IPAddr.new(body)
  raise 'proxy_preflight_failed' unless response.code == 200 && address.ipv4? && address.to_s == body && body == proxy.upstream_host

  puts 'instagram_coordination_preflight_ok'
rescue StandardError
  abort 'instagram_coordination_preflight_failed'
end
