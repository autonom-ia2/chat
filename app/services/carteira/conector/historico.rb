# As buscas no conector que a conta já fez (E7, #2900), a mais nova primeiro, no formato da tela: as TETO mais recentes.
# A de todo dia aparece como "chegou do Agger" (`diaria`), com Desfazer pela mesma regra dos PDFs
# (Carteira::Trazer::Pdfs::Desfazer: sai só o que veio na busca e em que ninguém mexeu). A primeira que ainda está no
# Conferir aparece também: a pessoa volta a ela por aqui. A de todo dia que não trouxe nada não aparece.
class Carteira::Conector::Historico
  TETO = Carteira::Trazer::Pdfs::Historico::TETO

  def initialize(buscas)
    @buscas = buscas
  end

  def call
    @buscas.includes(:user).order(created_at: :desc, id: :desc).limit(TETO).filter_map { |busca| item(busca) }
  end

  private

  def item(busca)
    totais = busca.totais.to_h
    diaria = totais.key?(Carteira::Leitura::DIARIA)
    return if diaria && busca.estado == 'trazida' && totais['seguros'].to_i.zero?

    { id: busca.id, origem: 'conector', diaria: diaria, quando: (busca.confirmada_em || busca.created_at).utc.iso8601, quem: busca.user&.name,
      situacao: busca.estado, seguros: totais['seguros'].to_i, pessoas: totais['pessoas'].to_i,
      podeDesfazer: Carteira::Trazer::Pdfs::Desfazer.pode?(busca) }
  end
end
