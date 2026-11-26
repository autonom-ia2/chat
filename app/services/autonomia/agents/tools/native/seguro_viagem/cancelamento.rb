# OS PRAZOS DE CANCELAMENTO (#3246) que a proposta diz ao modelo, da regra de cancelamento do plano guardada na
# cotação (`Planos#regra_cancelamento`: faixas `{ de, ate, multa, geraCredito }`). Decisão do Rodrigo: as duas datas.
#
# A Universal manda as faixas sem multa assim (medido em 26/11, viagem em 10/03/2027):
#   [{ de 26/11, ate 2026-12-03T00:00, multa 0 }, { de 04/12, ate 2027-03-09T00:00, multa 0 }]
# A primeira é o direito de arrependimento (7 dias): devolve tudo. A segunda vai até a véspera da viagem, e pelas
# condições gerais (cláusulas 14.1.3 e 14.2) a devolução é proporcional e o IOF não volta. Viagem dentro de 7 dias
# vem com uma faixa só.
#
#   devolucao_integral_ate       o fim da faixa sem multa que contém HOJE (no fuso da conta);
#   cancela_antes_da_viagem_ate  o fim da última faixa sem multa, só quando ela é outra, depois da primeira.
#
# O `ate` à meia-noite (`2026-12-03T00:00:00`) quer dizer "até o fim do dia anterior" (02/12/2026). Faixa sem multa
# legível (ausente, texto) ou sem data legível não conta, e prazo que já passou não é prazo: nunca uma data inventada.
module Autonomia::Agents::Tools::Native::SeguroViagem::Cancelamento
  Faixa = Struct.new(:inicio, :fim)

  module_function

  # `hoje`: a data de hoje no fuso da conta. -> { 'devolucao_integral_ate' => 'dd/mm/aaaa' ou nil,
  # 'cancela_antes_da_viagem_ate' => 'dd/mm/aaaa' ou nil }
  def prazos(plano, hoje:)
    faixas = Array(plano.to_h['regra_cancelamento']).filter_map { |regra| sem_multa(regra) }.select { |faixa| faixa.fim >= hoje }
    integral = faixas.select { |faixa| faixa.inicio.nil? || faixa.inicio <= hoje }.min_by(&:fim)
    { 'devolucao_integral_ate' => texto(integral), 'cancela_antes_da_viagem_ate' => texto(depois_da(integral, faixas)) }
  end

  # A última faixa, só quando ela termina depois da que contém hoje (ou quando nenhuma contém hoje).
  def depois_da(integral, faixas)
    ultima = faixas.max_by(&:fim)
    return ultima if integral.nil?

    ultima if ultima.fim > integral.fim
  end

  # -> a `Faixa` (datas) de uma regra sem multa, ou nil.
  def sem_multa(regra)
    return unless regra.is_a?(Hash) && BigDecimal(regra['multa'].to_s, exception: false)&.zero? == true

    ate = DateTime.iso8601(regra['ate'].to_s)
    Faixa.new(inicio(regra['de']), meia_noite?(ate) ? ate.to_date - 1 : ate.to_date)
  rescue Date::Error
    nil
  end

  # O começo da faixa; sem `de` legível, a faixa vale desde sempre.
  def inicio(comeco)
    DateTime.iso8601(comeco.to_s).to_date
  rescue Date::Error
    nil
  end

  def meia_noite?(momento)
    [momento.hour, momento.minute, momento.second, momento.second_fraction].all?(&:zero?)
  end

  def texto(faixa)
    faixa&.fim&.strftime('%d/%m/%Y')
  end

  private_class_method :depois_da, :sem_multa, :inicio, :meia_noite?, :texto
end
