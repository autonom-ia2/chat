class EmailCampaigns::DomainValidator
  MAX_TTL = 3600
  UNKNOWN_TTL = 300

  def initialize(resolver:, cache:, clock: -> { Time.now.utc })
    @resolver = resolver
    @cache = cache
    @clock = clock
    @local_cache = {}
  end

  def call(domain)
    domain = domain.downcase
    key = "email-hygiene:dns:v1:#{domain}"
    local = @local_cache[key]
    return local if local && local[:valid_until] > @clock.call

    cached = @cache.respond_to?(:read) ? @cache.read(key) : @cache[key]
    return @local_cache[key] = cached if cached && cached[:valid_until] > @clock.call

    result = resolve(domain)
    @local_cache[key] = result
    if @cache.respond_to?(:write)
      @cache.write(key, result, expires_in: [result[:valid_until] - @clock.call, 1].max)
    else
      @cache[key] = result
    end
    result
  end

  private

  def resolve(domain)
    mx = @resolver.call(domain, :MX)
    return result('invalid', 'nxdomain', [mx]) if mx[:status] == :nxdomain
    return unknown(mx, [mx]) unless mx[:status] == :ok

    return mx_result(mx) unless mx.fetch(:records).empty?

    implicit_route(domain, mx)
  end

  def mx_result(answer)
    records = answer.fetch(:records)
    return result('invalid', 'null_mx', [answer]) if records == [[0, '.']] || records == [[0, '']]
    return result('unknown', 'mixed_null_mx', [answer]) if records.any? { |_priority, exchange| exchange.to_s.delete_suffix('.').empty? }

    result('valid', 'mx', [answer])
  end

  def implicit_route(domain, mail_exchange)
    addresses = [@resolver.call(domain, :A)]
    addresses << @resolver.call(domain, :AAAA) unless routable?(addresses.first)
    answers = [mail_exchange, *addresses]
    return result('valid', 'implicit_mx', answers) if addresses.any? { |answer| routable?(answer) }

    uncertain = addresses.find { |answer| answer[:status] != :ok && answer[:status] != :nxdomain }
    return unknown(uncertain, answers) if uncertain

    result('invalid', 'no_mail_route', answers)
  end

  def routable?(answer)
    answer[:status] == :ok && answer.fetch(:records).any?
  end

  def unknown(answer, answers)
    result('unknown', "dns_#{answer.fetch(:status)}", answers)
  end

  def result(status, reason, answers)
    ceiling = status == 'unknown' ? UNKNOWN_TTL : MAX_TTL
    ttl = [*answers.map { |answer| answer.fetch(:ttl, ceiling).to_i }, ceiling].min.clamp(0, ceiling)
    { status: status, reason_code: reason, valid_until: @clock.call + ttl }
  end
end
