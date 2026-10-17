# Rails runner only: never invoke Meta or print transport exceptions/credentials.
# On failure prints only the generic token plus a fixed step code (#1540), never the exception.
# Tells check.sh the script itself ran (Docker and Rails boot are not Instagram's failures).
warn 'instagram_coordination_preflight_rails_started'
step = 'coordination_ping_failed'
begin
  coordination = Instagram::Testers::CoordinationRedis
  # with verifies integrity:epoch on this same connection before yielding.
  coordination.with { |redis| raise 'coordination_ping_failed' unless redis.ping == 'PONG' }
  step = 'proxy_configuration_invalid'
  proxy = Instagram::Testers::Proxy.new
  raise 'proxy_configuration_invalid' unless proxy.valid?

  step = 'proxy_preflight_failed'
  response = HTTParty.get('https://ipv4.webshare.io/', **proxy.transport_options,
                         timeout: 10, follow_redirects: false)
  body = response.body.to_s.strip
  address = IPAddr.new(body)
  raise 'proxy_preflight_failed' unless response.code == 200 && address.ipv4? && address.to_s == body && body == proxy.upstream_host

  puts 'instagram_coordination_preflight_ok'
rescue StandardError, ScriptError
  abort "instagram_coordination_preflight_failed step=#{step}"
end
