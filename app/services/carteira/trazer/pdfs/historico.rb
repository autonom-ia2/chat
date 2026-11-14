# Os lotes de "Trazer por PDFs" que a conta já enviou (E6.3, #2899), o mais novo primeiro, no formato da tela: os TETO
# mais recentes. Recebe o escopo dos lotes da conta. O lote que ainda está no Conferir aparece também: a pessoa volta a
# ele por aqui.
class Carteira::Trazer::Pdfs::Historico
  TETO = 50

  def initialize(lotes)
    @lotes = lotes
  end

  def call
    @lotes.includes(:user).order(created_at: :desc, id: :desc).limit(TETO).map { |lote| item(lote) }
  end

  private

  def item(lote)
    totais = lote.totais.to_h
    { id: lote.id, quando: (lote.confirmada_em || lote.created_at).utc.iso8601, quem: lote.user&.name, situacao: lote.estado,
      pdfs: totais[Carteira::Leitura::DO_TRAZER].to_i, seguros: totais['seguros'].to_i, pessoas: totais['pessoas'].to_i,
      podeDesfazer: Carteira::Trazer::Pdfs::Desfazer.pode?(lote) }
  end
end
