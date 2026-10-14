# #1460 — as datas de um lembrete que repete, no fuso da série. A hora de parede não anda: 10:00 continua 10:00 no
# horário de verão (TimeWithZone#advance conta em hora local). "Todo mês" é pelo dia do começo; no mês que não tem
# esse dia, cai no último dia (advance faz isso) e volta ao dia certo no mês seguinte, porque cada vez é contada a
# partir do começo, não da vez anterior.
class Crm::FollowUps::SeriesSchedule
  # Teto de voltas: toda semana num só dia com 500 vezes dá 3.500 dias.
  MAX_STEPS = 10_000
  STEP = { 'daily' => :days, 'weekly' => :days, 'monthly' => :months, 'yearly' => :years }.freeze

  def initialize(series)
    @series = series
  end

  # As vezes da série, em ordem, até o fim escolhido (ou até MAX_STEPS). Com `from`, começa perto dessa data (série
  # sem número de vezes), para uma série antiga não ser recontada desde o começo.
  def each_occurrence(from: nil)
    return enum_for(:each_occurrence, from: from) unless block_given?

    count = 0
    first = first_step(from)
    (first...(first + MAX_STEPS)).each do |step|
      candidate = anchor.advance(STEP.fetch(@series.frequency) => step)
      break if after_end_date?(candidate)
      next unless included?(candidate)

      count += 1
      break if count_reached?(count)

      yield candidate
    end
  end

  # As próximas vezes depois de `time` (exclusivo).
  def occurrences_after(time, limit:)
    each_occurrence(from: time).lazy.select { |occurrence| occurrence > time }.first(limit)
  end

  def next_after(time)
    occurrences_after(time, limit: 1).first
  end

  # As vezes dentro de uma janela (calendário).
  def between(from, to)
    each_occurrence(from: from).lazy.reject { |occurrence| occurrence < from }.take_while { |occurrence| occurrence <= to }.to_a
  end

  private

  def anchor
    @anchor ||= @series.starts_at.in_time_zone(@series.timezone)
  end

  # Um passo antes da data pedida (a conta de "vezes" precisa começar do começo).
  def first_step(from)
    return 0 if from.nil? || @series.ends_after_count?

    [steps_until(from.in_time_zone(@series.timezone)) - 1, 0].max
  end

  def steps_until(local)
    case @series.frequency
    when 'monthly' then month_index(local) - month_index(anchor)
    when 'yearly' then local.year - anchor.year
    else (local.to_date - anchor.to_date).to_i
    end
  end

  def month_index(time) = (time.year * 12) + time.month

  def included?(candidate)
    return @series.weekdays.include?(candidate.wday) if @series.weekly?
    return candidate.on_weekday? if @series.daily? && @series.weekdays_only?

    true
  end

  def after_end_date?(candidate)
    @series.ends_on_date? && @series.ends_on.present? && candidate.to_date > @series.ends_on
  end

  def count_reached?(count)
    @series.ends_after_count? && count > @series.occurrences_count.to_i
  end
end
