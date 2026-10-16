# A hora do WhatsApp de um evento que o motor manda (chat#1709, revisão da rodada 2): o voto (`vote.timestamp`, em
# segundos), a resposta ao evento (`timestampMs`), a ligação e a reação quando o conector mandar `timestamp`.
# Voto, resposta e reação são "um por autor, o novo substitui": seguir a ORDEM DE CHEGADA deixava um job refeito (fila
# com retry) trocar a escolha atual pela antiga. Com a hora do evento, a entrada do mesmo autor só é substituída por
# outra igual ou mais nova (`replaces?`).
module Waha::RichNative::EventTime
  # Número a partir do qual o valor é milissegundo: em segundos seria o ano 5138; em milissegundos, 1973.
  MS_THRESHOLD = 100_000_000_000
  EARLIEST = Time.utc(2009, 1, 1)
  # Relógio do aparelho adiantado: até isto no futuro ainda vale.
  FUTURE_SKEW = 1.day

  module_function

  # O epoch (segundos ou milissegundos, número ou texto numérico) como Time, ou nil quando não é uma hora plausível.
  def at(value)
    seconds = epoch_seconds(value)
    return if seconds.nil?

    time = Time.zone.at(seconds)
    time if time.between?(EARLIEST, FUTURE_SKEW.from_now)
  end

  def epoch_seconds(value)
    number = value.is_a?(String) ? Float(value, exception: false) : value
    return unless number.is_a?(Numeric) && number.to_f.finite? && number.positive?

    number >= MS_THRESHOLD ? number / 1000.0 : number
  end

  # ISO 8601 da hora do evento; sem ela, a hora de agora.
  def iso8601(value)
    (at(value) || Time.current).iso8601
  end

  # A entrada nova (hora `new_at`, ISO 8601) pode substituir a guardada (`stored_at`)? Sem hora guardada legível, sim.
  def replaces?(new_at, stored_at)
    stored = parse(stored_at)
    fresh = parse(new_at)
    stored.nil? || fresh.nil? || fresh >= stored
  end

  def parse(text)
    Time.iso8601(text.to_s)
  rescue ArgumentError
    nil
  end
end
