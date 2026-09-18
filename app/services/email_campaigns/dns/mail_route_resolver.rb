require 'resolv'
require 'timeout'

class EmailCampaigns::Dns::MailRouteResolver
  # Resolv#getresources conflates NXDOMAIN and NODATA. Observe errors before Config
  # consumes them; only an actual successful response with no records is NODATA.
  class ObservedConfig < Resolv::DNS::Config
    attr_reader :failure

    def resolv(name)
      super do |*args|
        yield(*args)
      rescue Resolv::DNS::Config::NXDomain
        @failure = :nxdomain
        raise
      rescue Resolv::DNS::Config::OtherResolvError
        @failure = :resolver_error
        raise
      rescue Resolv::ResolvTimeout
        @failure = :timeout
        raise
      end
    end
  end

  # Private stdlib extension kept beside the adapter whose NXDOMAIN semantics it supplies.
  class Resolver < Resolv::DNS # rubocop:disable Style/OneClassPerFile
    attr_reader :observed_config

    def initialize(config = Resolv::DNS::Config.default_config_hash)
      # Limit to one configured nameserver and one timeout. Absolute names avoid
      # search-domain expansion. Resolv still handles truncation via TCP.
      super(nameserver: config.fetch(:nameserver).first(1), search: [], ndots: 1)
      @observed_config = ObservedConfig.new(nameserver: config.fetch(:nameserver).first(1), search: [], ndots: 1)
      @config = @observed_config
      self.timeouts = [2]
    end
  end

  def initialize(timeout: 2, resolver: Resolver)
    raise ArgumentError, 'DNS deadline must be positive and at most two seconds' unless timeout.positive? && timeout <= 2

    @timeout = timeout
    @resolver = resolver
  end

  def call(domain, type)
    # Covers UDP, truncated-response TCP connect, writes and partial frame reads.
    # Resolv.open/fetch_resource ensure closes the resolver and all requesters.
    Timeout.timeout(@timeout) do
      @resolver.open { |dns| query(dns, domain, type) }
    end
  rescue Timeout::Error
    failure(:timeout)
  rescue Resolv::ResolvError, IOError, SystemCallError
    failure(:resolver_error)
  end

  private

  def query(dns, domain, type)
    answer = { status: nil, records: [], ttl: EmailCampaigns::DomainValidator::MAX_TTL }
    typeclass = Resolv::DNS::Resource::IN.const_get(type)
    dns.fetch_resource("#{domain}.", typeclass) do |reply, name|
      answer[:status] = :ok
      answer[:ttl] = [answer[:ttl], *response_ttls(reply)].min
      dns.extract_resources(reply, name, typeclass) do |record|
        answer[:records] << (type == :MX ? [record.preference, record.exchange.to_s] : record.address.to_s)
      end
    end
    answer[:status] ||= dns.observed_config.failure || :resolver_error
    # NXDOMAIN's negative packet TTL is consumed by Resolv; do not invent one.
    answer[:ttl] = 0 if answer[:status] == :nxdomain
    answer
  end

  def response_ttls(reply)
    reply.answer.map { |_name, seconds, _record| seconds } + reply.authority.map do |_name, seconds, record|
      record.respond_to?(:minimum) ? [seconds, record.minimum].min : seconds
    end
  end

  def failure(status)
    { status: status, records: [], ttl: EmailCampaigns::DomainValidator::UNKNOWN_TTL }
  end
end
