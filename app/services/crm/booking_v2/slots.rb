# Horários livres de uma página nova (#1188), sem depender de caixa de e-mail.
#
# Regras do perfil: dias e horário de trabalho (`weekdays`, `start_hour`, `end_hour`), antecedência mínima
# (`min_notice_minutes`), intervalo entre reuniões (`buffer_minutes`), janela (`booking_window_days`), fuso
# (`resolved_timezone`) e duração escolhida, que precisa estar em `profile.durations`.
#
# Ocupação = reuniões `scheduled` do responsável (`created_by_id`, de qualquer caixa e as internas sem caixa) MAIS o
# freebusy do provedor quando a página tem caixa de e-mail com calendário Google/Microsoft. Em `strict: true` (hora de
# reservar) o freebusy não vem do cache e qualquer erro do provedor vira ArgumentError 'availability_unavailable'
# (falha fechada). Fora do modo estrito o erro do provedor é registrado e a tela mostra só a ocupação local.
#
# Caixa compartilhada (`calendar_shared?`, ex.: um comercial@ da equipe toda): o freebusy é da caixa inteira e
# bloquearia horários de outras pessoas, então fica só a ocupação do responsável (mesma regra do v1).
#
# `include_provider: false` pula o provedor: o Booker consulta o provedor ANTES das travas (rede lenta não segura
# trava) e, dentro delas, reconfere só a ocupação local.
#
# `next_slot` faz UMA consulta ao provedor para todo o intervalo varrido (no máximo 14 dias ou a janela, se menor),
# com cache de 5 minutos, e varre os dias localmente.
#
# Equipe (#1195): com `close_holidays` ligado (padrão) nenhum feriado nacional (`Crm::Calendar::Holidays`, no fuso
# do perfil) é oferecido. "Meus horários" (`Crm::AgentAvailability` do responsável): agenda pausada não oferece
# horário; dias e horas próprios valem só na INTERSEÇÃO com os da página, nunca além deles.
class Crm::BookingV2::Slots
  CACHE_TTL = 5.minutes
  MAX_SCAN_DAYS = 14
  MAX_SLOTS = 200

  def self.next_slot(profile:, host:, from: Time.current, duration: nil)
    new(profile: profile, host: host, date: nil, duration: duration).first_free(from)
  end

  # Reuniões `scheduled` da pessoa que cruzam o intervalo, de qualquer caixa e as internas. Também usada por quem
  # confere conflito fora da página (Reassigner), sob a mesma trava de agente.
  def self.busy_intervals(account_id:, host_id:, from:, to:)
    Crm::Meeting.where(account_id: account_id, created_by_id: host_id, status: :scheduled)
                .where('starts_at < ? AND ends_at > ?', to, from)
                .pluck(:starts_at, :ends_at)
                .map { |start_at, end_at| { start: start_at, end: end_at } }
  end

  def initialize(profile:, host:, date:, duration: nil, strict: false, include_provider: true) # rubocop:disable Metrics/ParameterLists
    @profile = profile
    @host = host
    @date = date
    @strict = strict
    @include_provider = include_provider
    @duration = resolve_duration!(duration).minutes
  end

  # Inícios livres do dia `date` (YYYY-MM-DD no fuso do perfil), como ISO8601 com offset.
  def perform
    day = parse_date
    return [] if day.nil? || host_paused? || !bookable_day?(day)

    busy = busy_between(day_start(day), day_end(day))
    free_starts(day, busy, earliest_start).first(MAX_SLOTS).map(&:iso8601)
  end

  def first_free(from)
    return if host_paused?

    earliest = [earliest_start, from].max
    days = scan_days(earliest.in_time_zone(time_zone).to_date)
    return if days.empty?

    busy = busy_between(day_start(days.first), day_end(days.last))
    days.each do |day|
      slot = free_starts(day, busy, earliest).first
      return slot.iso8601 if slot
    end
    nil
  end

  private

  attr_reader :profile, :host, :strict, :duration, :include_provider

  def resolve_duration!(value)
    minutes = value.nil? ? profile.duration_minutes : Integer(value.to_s, exception: false)
    raise ArgumentError, 'invalid_duration' unless profile.durations.include?(minutes)

    minutes
  end

  def time_zone
    @time_zone ||= ActiveSupport::TimeZone[profile.resolved_timezone] || ActiveSupport::TimeZone['UTC']
  end

  def parse_date
    Date.iso8601(@date.to_s)
  rescue Date::Error
    nil
  end

  def today
    Time.current.in_time_zone(time_zone).to_date
  end

  def last_bookable_day
    today + profile.booking_window_days
  end

  def bookable_day?(day)
    weekdays.include?(day.wday) && start_hour < end_hour && day >= today && day <= last_bookable_day && !closed_holiday?(day)
  end

  def closed_holiday?(day)
    profile.close_holidays? && Crm::Calendar::Holidays.holiday?(day)
  end

  def availability
    return @availability if defined?(@availability)

    @availability = host.present? ? Crm::AgentAvailability.find_by(account_id: profile.account_id, user_id: host.id) : nil
  end

  def host_paused?
    availability&.paused? || false
  end

  def own_hours?
    availability.present? && availability.custom_hours?
  end

  def weekdays
    @weekdays ||= own_hours? ? profile.weekdays & availability.weekdays : profile.weekdays
  end

  def start_hour
    own_hours? ? [profile.start_hour, availability.start_hour].max : profile.start_hour
  end

  def end_hour
    own_hours? ? [profile.end_hour, availability.end_hour].min : profile.end_hour
  end

  def scan_days(first_day)
    last_day = [last_bookable_day, today + MAX_SCAN_DAYS].min
    (first_day..last_day).select { |day| bookable_day?(day) }
  end

  def day_start(day)
    time_zone.local(day.year, day.month, day.day, start_hour)
  end

  def day_end(day)
    return time_zone.local(day.year, day.month, day.day) + 1.day if end_hour >= 24

    time_zone.local(day.year, day.month, day.day, end_hour)
  end

  def buffer
    profile.buffer_minutes.minutes
  end

  def earliest_start
    Time.current + [profile.min_notice_minutes.to_i.minutes, buffer].max
  end

  def free_starts(day, busy, earliest)
    starts = []
    cursor = day_start(day)
    limit = day_end(day)
    while cursor + duration <= limit
      starts << cursor if cursor >= earliest && !conflicts?(cursor, busy)
      cursor += duration
    end
    starts
  end

  def conflicts?(start_at, busy)
    window_start = start_at - buffer
    window_end = start_at + duration + buffer
    busy.any? { |interval| window_start < interval[:end] && interval[:start] < window_end }
  end

  def busy_between(range_start, range_end)
    host_intervals(range_start - buffer, range_end + buffer) + provider_intervals(range_start, range_end)
  end

  def host_intervals(range_start, range_end)
    return [] if host.blank?

    self.class.busy_intervals(account_id: profile.account_id, host_id: host.id, from: range_start, to: range_end)
  end

  def provider_intervals(range_start, range_end)
    return [] if !include_provider || calendar_channel.blank? || calendar_channel.calendar_shared? || simulated?
    return fetch_strict(range_start, range_end) if strict

    cached_provider_intervals(range_start, range_end)
  end

  def cached_provider_intervals(range_start, range_end)
    Rails.cache.fetch(cache_key(range_start, range_end), expires_in: CACHE_TTL) { fetch_provider(range_start, range_end, false) }
  rescue StandardError => e
    Rails.logger.error("CRM booking v2 free/busy failed: #{e.class.name}")
    []
  end

  def fetch_strict(range_start, range_end)
    fetch_provider(range_start, range_end, true)
  rescue StandardError
    raise ArgumentError, 'availability_unavailable'
  end

  def fetch_provider(range_start, range_end, raise_on_error)
    service = if calendar_channel.microsoft?
                Microsoft::FreeBusyService.new(channel: calendar_channel, time_min: range_start, time_max: range_end,
                                               email: calendar_channel.calendar_organizer_email)
              else
                Google::FreeBusyService.new(channel: calendar_channel, time_min: range_start, time_max: range_end)
              end
    service.busy_intervals(raise_on_error: raise_on_error).map { |slot| { start: slot[:start], end: slot[:end] } }
  end

  def cache_key(range_start, range_end)
    "crm_booking_v2_freebusy:#{profile.inbox_id}:#{range_start.to_i}:#{range_end.to_i}"
  end

  def simulated?
    calendar_channel.microsoft? ? Crm::Config.calendar_ms_simulate? : Crm::Config.calendar_google_simulate?
  end

  def calendar_channel
    return @calendar_channel if defined?(@calendar_channel)

    channel = profile.inbox&.channel
    calendar = channel.is_a?(Channel::Email) && channel.calendar_enabled? && (channel.google? || channel.microsoft?)
    @calendar_channel = calendar ? channel : nil
  end
end
