# OAuth Client ID Metadata Document (draft-ietf-oauth-client-id-metadata-document).
# The client_id is the https URL of a public JSON document that names the client and its redirect URIs.
# Em d.ia connects this way, without registering and without a secret; Claude and ChatGPT may too.
#
# The document is fetched from a URL chosen by whoever starts the flow, so the fetch is the attack surface:
# https only, no redirects, the host must resolve only to public addresses and the connection goes to the
# address that was checked (no second DNS lookup), port 443 only, a deadline for the whole fetch and a small
# size cap. A document that failed is not fetched again for a while.
class Oauth::ClientMetadataDocument
  class Invalid < StandardError; end

  MAX_BYTES = 16.kilobytes
  TIMEOUT_SECONDS = 3
  # Per-read timeouts alone let a server that trickles one byte at a time hold the web thread much longer.
  TOTAL_SECONDS = 5
  REJECTED_FOR = 10.minutes
  MAX_URL_LENGTH = 255
  MAX_REDIRECT_URIS = 10
  # A known client is refreshed at most this often, so a changed document takes effect without hammering it.
  REFRESH_AFTER = 1.hour
  # Besides private/loopback/link-local: carrier NAT, IETF, benchmarking, multicast/reserved, and the IPv6 forms that
  # can carry an IPv4 address (IPv4-compatible, NAT64, 6to4).
  RESERVED_RANGES = %w[0.0.0.0/8 100.64.0.0/10 192.0.0.0/24 198.18.0.0/15 224.0.0.0/3
                       ::/96 64:ff9b::/96 2002::/16 fc00::/7 ff00::/8].map { |range| IPAddr.new(range) }.freeze
  FETCH_ERRORS = [JSON::ParserError, SocketError, SystemCallError, IOError, Timeout::Error, OpenSSL::SSL::SSLError,
                  Net::HTTPBadResponse, Net::ProtocolError, Zlib::Error].freeze

  def self.url?(client_id)
    value = client_id.to_s
    value.start_with?('https://') && value.length <= MAX_URL_LENGTH
  end

  # Creates or refreshes the Doorkeeper application for this document. A document that cannot be read or is not
  # valid leaves the client unknown (or as it was), so Doorkeeper answers invalid_client as for any unknown id.
  def self.sync(client_id)
    application = Doorkeeper::Application.find_by(uid: client_id)
    return application if application && application.updated_at > REFRESH_AFTER.ago
    return application if Rails.cache.exist?(rejected_key(client_id))

    save(application || Doorkeeper::Application.new(uid: client_id, confidential: false), new(client_id).application_attributes)
  rescue Invalid, ActiveRecord::RecordInvalid => e
    reject(client_id, e)
    application
  rescue ActiveRecord::RecordNotUnique
    Doorkeeper::Application.find_by(uid: client_id)
  end

  # An unchanged document still counts as checked now, so it is not fetched again on every authorization.
  def self.save(application, attributes)
    application.assign_attributes(attributes)
    application.new_record? || application.changed? ? application.save! : application.touch # rubocop:disable Rails/SkipsModelValidations
    application
  end

  def self.reject(client_id, error)
    Rails.cache.write(rejected_key(client_id), true, expires_in: REJECTED_FOR)
    # The id may not even parse as a URL, so the host is cut out as text.
    host = client_id.to_s.delete_prefix('https://').split('/').first.to_s.truncate(100)
    Rails.logger.info("oauth.client_metadata_document rejected host=#{host} reason=#{error.message}")
  end

  def self.rejected_key(client_id)
    "oauth:client_metadata_document:rejected:#{Digest::SHA256.hexdigest(client_id.to_s)}"
  end
  private_class_method :save, :reject, :rejected_key

  def initialize(url)
    @uri = URI.parse(url)
    raise Invalid, 'not https' unless @uri.is_a?(URI::HTTPS) && @uri.host.present? && @uri.userinfo.nil? && @uri.fragment.nil?
    raise Invalid, 'not port 443' unless @uri.port == 443
  rescue URI::InvalidURIError
    raise Invalid, 'bad url'
  end

  def application_attributes
    document = fetch_document
    raise Invalid, 'client_id differs' unless document['client_id'] == @uri.to_s

    {
      name: client_name(document),
      redirect_uri: redirect_uris(document).join("\n"),
      # The document's own scope list is not used: one document may serve many services (Em d.ia lists the scopes
      # of all of them). Each authorization request still asks for scopes, and Doorkeeper checks those.
      scopes: '',
      confidential: false
    }
  end

  private

  def client_name(document)
    name = document['client_name']
    name.is_a?(String) && name.strip.present? ? name.strip.truncate(100) : @uri.host
  end

  def redirect_uris(document)
    uris = document['redirect_uris']
    raise Invalid, 'redirect_uris' unless uris.is_a?(Array) && uris.size.between?(1, MAX_REDIRECT_URIS)
    raise Invalid, 'redirect_uri not https' unless uris.all? { |uri| uri.is_a?(String) && uri.start_with?('https://') }

    uris
  end

  def fetch_document
    parsed = JSON.parse(Timeout.timeout(TOTAL_SECONDS) { read_document })
    raise Invalid, 'not an object' unless parsed.is_a?(Hash)

    parsed
  rescue *FETCH_ERRORS => e
    raise Invalid, "fetch failed (#{e.class.name})"
  end

  def read_document
    body = +''
    http_client.request(Net::HTTP::Get.new(@uri.request_uri, 'Accept' => 'application/json')) do |response|
      raise Invalid, "status #{response.code}" unless response.is_a?(Net::HTTPOK)

      response.read_body do |chunk|
        body << chunk
        raise Invalid, 'too large' if body.bytesize > MAX_BYTES
      end
    end
    body
  end

  # Connects to the address that was checked, not to a second DNS answer (no rebinding between check and use).
  def http_client
    Net::HTTP.new(@uri.host, @uri.port).tap do |http|
      http.ipaddr = public_address
      http.use_ssl = true
      http.open_timeout = TIMEOUT_SECONDS
      http.read_timeout = TIMEOUT_SECONDS
      http.write_timeout = TIMEOUT_SECONDS
    end
  end

  # Every address of the host must be public; the request then goes to the first one.
  def public_address
    addresses = Resolv.getaddresses(@uri.host)
    raise Invalid, 'no address' if addresses.empty?

    ips = addresses.map { |address| IPAddr.new(address) }
    raise Invalid, 'private address' if ips.any? { |ip| private_ip?(ip) }

    ips.first.to_s
  end

  def private_ip?(ip)
    ip = ip.native if ip.ipv4_mapped?
    ip.private? || ip.loopback? || ip.link_local? || reserved?(ip)
  end

  def reserved?(ip)
    RESERVED_RANGES.any? { |range| range.family == ip.family && range.include?(ip) }
  end
end
