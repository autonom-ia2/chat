# O andamento de um lote de PDFs depois do "Trazer" (E6.3, #2899), como a tela lê:
#
#   { id:, estado: 'trazendo' | 'trazida' | 'desfazendo' | 'desfeita', porcentagem:, seguros:, pessoas:, pessoasNovas:,
#     naoEntraram:, naoEntraramPorque: { semDocumento:, dadosErrados:, outros: } }
#
# Enquanto grava, a porcentagem é dos PDFs prontos que já passaram (entraram ou não); os números são os de agora.
# `naoEntraramPorque` (só depois de gravar) abre o `naoEntraram` pelo motivo que o gravador contou (`motivo_<código>`),
# para a tela dizer por quê (a busca no Agger, #2900): sem a pessoa (`sem_pessoa`: sem CPF/CNPJ e sem seguro guardado),
# com dado que o seguro recusa (`invalido`) e o resto. A soma é o `naoEntraram`.
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
      pessoasNovas: totais['pessoas_novas'].to_i, naoEntraram: totais['nao_entraram'].to_i, naoEntraramPorque: porque(totais) }
  end

  def porque(totais)
    sem_documento = totais['motivo_sem_pessoa'].to_i
    dados_errados = totais['motivo_invalido'].to_i
    { semDocumento: sem_documento, dadosErrados: dados_errados,
      outros: [totais['nao_entraram'].to_i - sem_documento - dados_errados, 0].max }
  end

  def porcentagem(totais)
    total = totais['para_trazer'].to_i
    return 0 if total.zero?

    [(@leitura.itens.where(estado: PASSARAM).count * 100) / total, 99].min
  end
end
