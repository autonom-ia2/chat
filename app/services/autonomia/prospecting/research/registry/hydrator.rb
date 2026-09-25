# Busca até 3 CNPJs na cadeia de cadastros públicos, ao mesmo tempo (porte de registry/hydrator.ts do Orth).
#
# Por CNPJ: as fontes na ordem de Registry::PROVIDERS, 5 s por tentativa e 15 s no total. Fonte que falha, recusa,
# redireciona ou manda cadastro inválido passa a vez. Só 429 e 5xx com Retry-After de até 1 s ganham uma segunda
# tentativa, e só se ela ainda couber no prazo. A auditoria de cada tentativa não leva corpo nem mensagem de erro.
class Autonomia::Prospecting::Research::Registry::Hydrator
  Registry = Autonomia::Prospecting::Research::Registry

  MAX_CANDIDATES = 3
  ATTEMPT_TIMEOUT_SECONDS = 5
  CANDIDATE_DEADLINE_SECONDS = 15
  MAX_RETRY_AFTER_SECONDS = 1
  CNPJ_LENGTH = 14

  class AttemptTimeout < StandardError; end
  TIMEOUT_ERRORS = [AttemptTimeout, Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout, Timeout::Error].freeze
  MONOTONIC_CLOCK = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }

  def initialize(transport: Registry::HttpTransport.new, clock: MONOTONIC_CLOCK, sleeper: ->(seconds) { sleep(seconds) })
    @transport = transport
    @clock = clock
    @sleeper = sleeper
  end

  # Devolve uma Registry::Hydration por CNPJ, na ordem pedida.
  def hydrate(cnpjs)
    normalized = normalize(cnpjs)
    return normalized.map { |cnpj| hydrate_candidate(cnpj) } if normalized.size <= 1

    threads = normalized.map { |cnpj| Thread.new { hydrate_candidate(cnpj) } }
    ActiveSupport::Dependencies.interlock.permit_concurrent_loads { threads.map(&:value) }
  end

  private

  def normalize(cnpjs)
    raise ArgumentError, 'at most 3 CNPJs' if cnpjs.size > MAX_CANDIDATES

    normalized = cnpjs.map { |cnpj| Autonomia::Prospecting::Research::Normalization.digits(cnpj) }
    raise ArgumentError, 'requires 14-digit CNPJs' unless normalized.all? { |cnpj| cnpj.length == CNPJ_LENGTH }

    normalized
  end

  def hydrate_candidate(cnpj)
    started = @clock.call
    attempts = []
    Registry::PROVIDERS.each do |provider|
      break if elapsed(started) >= CANDIDATE_DEADLINE_SECONDS

      company = try_provider(provider, cnpj, started, attempts)
      return Registry::Hydration.new(cnpj: cnpj, company: company, failure_reason: nil, attempts: attempts.freeze) if company
    end
    reason = elapsed(started) >= CANDIDATE_DEADLINE_SECONDS ? :deadline_exceeded : :providers_exhausted
    Registry::Hydration.new(cnpj: cnpj, company: nil, failure_reason: reason, attempts: attempts.freeze)
  end

  def try_provider(provider, cnpj, started, attempts)
    response = attempt(provider, cnpj, started, attempts)
    company = company_from(provider, cnpj, response, attempts.last)
    return company if company

    wait = retry_after(response)
    return nil unless wait

    attempts.last['retry_after_ms'] = (wait * 1000).round
    return nil unless retry_fits?(wait, started)

    @sleeper.call(wait)
    retry_response = attempt(provider, cnpj, started, attempts, retry_of: attempts.size - 1)
    company_from(provider, cnpj, retry_response, attempts.last)
  end

  def retry_fits?(wait, started)
    wait <= MAX_RETRY_AFTER_SECONDS && elapsed(started) + wait + ATTEMPT_TIMEOUT_SECONDS <= CANDIDATE_DEADLINE_SECONDS
  end

  def attempt(provider, cnpj, started, attempts, retry_of: nil)
    audit = { 'provider' => provider.name }
    audit['retry_of'] = retry_of if retry_of
    attempt_started = @clock.call
    response = request(provider.url(cnpj), [ATTEMPT_TIMEOUT_SECONDS, CANDIDATE_DEADLINE_SECONDS - (attempt_started - started)].min)
    audit['outcome'] = outcome_for(response.status)
    audit['http_status'] = response.status
    response
  rescue *TIMEOUT_ERRORS
    audit['outcome'] = 'timeout'
    nil
  rescue Registry::HttpTransport::BodyTooLarge
    audit['outcome'] = 'body_too_large'
    nil
  rescue StandardError
    # A mensagem do erro pode trazer URL, token ou dado de terceiro: não entra na auditoria.
    audit['outcome'] = 'network_error'
    nil
  ensure
    audit['duration_ms'] = ((@clock.call - attempt_started) * 1000).round
    attempts << audit
  end

  def request(url, timeout)
    raise AttemptTimeout unless timeout.positive?

    Timeout.timeout(timeout, AttemptTimeout) { @transport.request(url: url, timeout: timeout) }
  end

  def outcome_for(status)
    return 'not_found' if status == 404
    return 'success' if (200..299).cover?(status)
    return 'redirect_refused' if (300..399).cover?(status)

    'http_error'
  end

  def company_from(provider, cnpj, response, audit)
    return nil unless response && (200..299).cover?(response.status)

    parsed = provider.parser.parse(requested_cnpj: cnpj, payload: response.body, fetched_at: Time.current)
    return parsed.company if parsed.valid?

    audit['outcome'] = 'semantic_invalid'
    audit['reason'] = parsed.reason
    nil
  end

  def retry_after(response)
    return nil unless response && (response.status == 429 || response.status >= 500)

    seconds(response.headers['retry-after'])
  end

  # Retry-After só em segundos; data HTTP ou lixo não valem.
  def seconds(value)
    seconds = Float(value.to_s.strip, exception: false)
    seconds if seconds&.finite? && !seconds.negative?
  end

  def elapsed(started) = @clock.call - started
end
