# O andamento de um lote de PDFs depois do "Trazer" (E6.3, #2899), como a tela lê:
#
#   { id:, estado: 'trazendo' | 'trazida' | 'desfazendo' | 'desfeita', porcentagem:, seguros:, pessoas:, pessoasNovas:,
#     naoEntraram: }
#
# Enquanto grava, a porcentagem é dos PDFs prontos que já passaram (entraram ou não); os números são os de agora.
class Carteira::Trazer::Pdfs::Andamento
  PASSARAM = %w[trazido nao_entrou].freeze

  def initialize(leitura)
    @leitura = leitura
  end

  def call
    totais = @leitura.totais.to_h
    return terminado(totais) unless @leitura.estado == 'trazendo'

    trazidos = @leitura.itens.where(estado: 'trazido')
    { id: @leitura.id, estado: @leitura.estado, porcentagem: porcentagem(totais), seguros: trazidos.count,
      pessoas: trazidos.distinct.count(:contact_id), pessoasNovas: nil, naoEntraram: @leitura.itens.where(estado: 'nao_entrou').count }
  end

  private

  def terminado(totais)
    { id: @leitura.id, estado: @leitura.estado, porcentagem: 100, seguros: totais['seguros'].to_i, pessoas: totais['pessoas'].to_i,
      pessoasNovas: totais['pessoas_novas'].to_i, naoEntraram: totais['nao_entraram'].to_i }
  end

  def porcentagem(totais)
    total = totais['para_trazer'].to_i
    return 0 if total.zero?

    [(@leitura.itens.where(estado: PASSARAM).count * 100) / total, 99].min
  end
end
