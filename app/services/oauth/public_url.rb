# The address an OAuth client must see for this installation.
# One installation can answer on more than one host (agents.autonomia.site and chat.autonomia.site are the same app).
# The metadata has to name the host the client used, or the client rejects it (RFC 8414 §3.3, RFC 9728 §3.3).
# Hosts other than FRONTEND_URL's are accepted only when listed in OAUTH_PROVIDER_EXTRA_HOSTS (comma separated).
module Oauth::PublicUrl
  def self.for(request)
    # Without FRONTEND_URL (test and some dev setups) the request's own address is the only one there is
    return request.base_url if frontend_url.blank?

    frontend = URI.parse(frontend_url)
    return frontend_url if request.host == frontend.host
    return frontend_url unless extra_hosts.include?(request.host)

    "#{frontend.scheme}://#{request.host}"
  end

  def self.extra_hosts
    ENV.fetch('OAUTH_PROVIDER_EXTRA_HOSTS', '').split(',').map(&:strip).compact_blank
  end

  def self.frontend_url
    ENV.fetch('FRONTEND_URL', '').delete_suffix('/')
  end
end
