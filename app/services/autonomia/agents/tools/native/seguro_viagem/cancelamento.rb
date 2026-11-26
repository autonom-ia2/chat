# ATÉ QUANDO CANCELA SEM CUSTO (#3246): o dia que a proposta diz ao modelo, da regra de cancelamento do plano guardada
# na cotação (`Planos#regra_cancelamento`: uma lista de `{ de, ate, multa, geraCredito }`).
#
# Vale o maior `ate` entre as faixas com multa zero. O `ate` à meia-noite (`2026-12-02T00:00:00`) quer dizer "até o
# fim do dia anterior": o dia dito é 01/12/2026. Faixa sem multa legível (ausente, texto) ou sem data legível não conta:
# nunca um prazo inventado. Dia que já passou não é prazo para o cliente. Sem faixa que conte, nil.
module Autonomia::Agents::Tools::Native::SeguroViagem::Cancelamento
  module_function

  # -> 'dd/mm/aaaa' ou nil.
  def sem_custo_ate(plano)
    dias = Array(plano.to_h['regra_cancelamento']).filter_map { |regra| ultimo_dia_sem_multa(regra) }
    ultimo = dias.max
    ultimo.strftime('%d/%m/%Y') if ultimo && ultimo >= Time.zone.today
  end

  def ultimo_dia_sem_multa(regra)
    return unless regra.is_a?(Hash) && sem_multa?(regra['multa'])

    ate = DateTime.iso8601(regra['ate'].to_s)
    meia_noite?(ate) ? ate.to_date - 1 : ate.to_date
  rescue Date::Error
    nil
  end

  def sem_multa?(multa)
    BigDecimal(multa.to_s, exception: false)&.zero? == true
  end

  def meia_noite?(momento)
    [momento.hour, momento.minute, momento.second, momento.second_fraction].all?(&:zero?)
  end

  private_class_method :ultimo_dia_sem_multa, :sem_multa?, :meia_noite?
end
