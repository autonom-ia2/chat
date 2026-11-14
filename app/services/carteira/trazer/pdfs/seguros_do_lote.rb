# "Trazer por PDFs" (E6.3, #2899): os seguros que um lote de PDFs pôs na carteira, diante de como estão hoje. O
# "Desfazer" do lote e a prévia dele leem por aqui, então o que a prévia promete é o que o Desfazer faz. Segue a regra
# do Desfazer da planilha (Carteira::Trazer::SegurosDaLista, #3003): só sai o que veio no lote e em que ninguém mexeu;
# na dúvida, fica.
#
# O que o gravador já deixa basta (Carteira::Guardar com a leitura, Carteira::Trazer::Pdfs::Gravar):
# - o seguro que o lote CRIOU aponta para a leitura (`leitura_id`) e tem o passo `chegou_pdf` dela;
# - o seguro que o lote só COMPLETOU ganhou o passo `chegou_de_novo_pdf` com o antes e o depois (e, se a origem subiu
#   da planilha para o PDF, a origem de antes);
# - o PDF que o lote pôs num seguro deixou o passo `pdf_anexado`. Os três levam o id da leitura em `valores`.
#
# SAI o seguro que o lote criou e em que ninguém mexeu: a história só tem passos do lote (nada de correção,
# cancelamento, outro PDF, renovação, outra lista); nenhuma outra leitura de PDF aponta para ele; não tem card de
# renovação, desfecho, apólice anterior nem apólice nova; não foi corrigido à mão; e a origem continua `pdf`. O PDF dele
# é o do lote (trocar o PDF deixaria outro passo) e sai junto.
# VOLTA ao que era o seguro que já existia e que o lote completou, se nenhum passo de outra origem veio depois do do
# lote, ele não está cancelado, não tem nada do que não deixa passo (card, desfecho, apólice nova, outra leitura) e cada
# campo mudado ainda tem o valor que o lote pôs. Voltam todos os campos e a origem, ou nada. O PDF que o lote pôs nele
# sai.
# FICA todo o resto. Tudo é lido só dentro da conta da leitura. Nada daqui vai para o log.
class Carteira::Trazer::Pdfs::SegurosDoLote
  DA_LISTA = Carteira::Trazer::SegurosDaLista
  DEPOIS_DO_LOTE = DA_LISTA::DEPOIS_DA_LISTA
  DE_NOVO = Carteira::Guardar::DE_NOVO_DA.fetch('pdf')
  BLOCO = DA_LISTA::BLOCO
  SO_PASSOS_DO_LOTE = 'NOT EXISTS (SELECT 1 FROM carteira_apolice_eventos passo WHERE passo.apolice_id = carteira_apolices.id ' \
                      "AND (passo.valores ->> 'leitura') IS DISTINCT FROM ?)".freeze
  SEM_OUTRA_LEITURA = 'NOT EXISTS (SELECT 1 FROM carteira_leitura_itens item WHERE item.apolice_id = carteira_apolices.id ' \
                      'AND item.leitura_id <> ?)'.freeze

  def initialize(leitura)
    @leitura = leitura
    @conta_id = leitura.account_id
    @marca = leitura.id.to_s
  end

  def saem
    criados.where(origem: 'pdf', de_fora: false).where(**(DEPOIS_DO_LOTE - [:leitura_id]).index_with { nil }).where(DA_LISTA::COMO_CHEGOU)
           .where(DA_LISTA::SEM_APOLICE_NOVA).where(SO_PASSOS_DO_LOTE, @marca).where(SEM_OUTRA_LEITURA, @leitura.id)
  end

  def sai?(apolice)
    saem.exists?(id: apolice.id)
  end

  # Bloco a bloco, os seguros completados pelo lote que voltam ao que eram.
  def que_voltam
    sem_cuidado_depois(completados).in_batches(of: BLOCO) do |apolices|
      yield(apolices.to_a.select { |apolice| volta(apolice) })
    end
  end

  # O que a apólice volta a ter, lido de novo: { colunas: { coluna => valor de antes }, tirar_pdf: }. nil: ela fica.
  def volta(apolice)
    return unless pode_voltar?(apolice)

    do_lote = passos_do_lote_por_ultimo(apolice)
    colunas = do_lote && colunas_de_antes(apolice, do_lote)
    return unless colunas

    tirar_pdf = do_lote.any? { |passo| passo.tipo == Carteira::Pdf::ANEXADO }
    { colunas: colunas, tirar_pdf: tirar_pdf } if colunas.any? || tirar_pdf
  end

  def pode_voltar?(apolice)
    apolice.cancelado_em.nil? && sem_cuidado_depois(completados).exists?(id: apolice.id)
  end

  def passos_do_lote_em(apolice)
    apolice.eventos.where("carteira_apolice_eventos.valores ->> 'leitura' = ?", @marca)
  end

  def previa
    saem = self.saem.count
    voltam = 0
    que_voltam { |bloco| voltam += bloco.size }
    { saem: saem, voltam: voltam, ficam: (criados.count - saem) + (completados.count - voltam) }
  end

  # Quantos seguros ainda trazem o lote: os que ele criou e continuam, e os que ele completou e não voltaram (os que
  # voltaram perdem os passos do lote). Depois do Desfazer, são os que ficaram.
  def ainda_do_lote
    criados.count + completados.count
  end

  private

  def criados
    Carteira::Apolice.where(account_id: @conta_id, leitura_id: @leitura.id)
  end

  def completados
    tocados = Carteira::ApoliceEvento.where(tipo: [DE_NOVO, Carteira::Pdf::ANEXADO])
                                     .where("carteira_apolice_eventos.valores ->> 'leitura' = ?", @marca).select(:apolice_id)
    Carteira::Apolice.where(account_id: @conta_id, id: tocados).where('carteira_apolices.leitura_id IS DISTINCT FROM ?', @leitura.id)
  end

  def sem_cuidado_depois(apolices)
    apolices.where(**DEPOIS_DO_LOTE.index_with { nil }).where(DA_LISTA::SEM_APOLICE_NOVA).where(SEM_OUTRA_LEITURA, @leitura.id)
  end

  def do_lote?(passo)
    passo.valores.to_h['leitura'].to_s == @marca
  end

  # Os passos do lote na história da apólice, se nenhum passo de outra origem veio depois deles; senão, nil.
  def passos_do_lote_por_ultimo(apolice)
    do_lote, de_fora = apolice.eventos.order(:id).partition { |passo| do_lote?(passo) }
    ultimo = do_lote.map(&:id).max
    do_lote if ultimo && de_fora.none? { |passo| passo.id > ultimo }
  end

  # Da mudança mais nova para a mais velha: cada campo tem de estar com o valor que o lote pôs; aí volta ao de antes. A
  # origem que o lote subiu (da planilha para o PDF) volta junto. nil: algum campo já mudou, e nada volta.
  def colunas_de_antes(apolice, do_lote)
    de_antes = {}
    do_lote.reverse_each do |passo|
      Array(passo.mudancas).reverse_each do |mudanca|
        return nil unless voltar_campo(apolice, mudanca, de_antes)
      end
      de_antes[:origem] = passo.valores['origem_antes'] if subiu_a_origem?(apolice, passo)
    end
    de_antes
  end

  def voltar_campo(apolice, mudanca, de_antes)
    coluna = Carteira::Campos::COLUNAS[mudanca['campo']]
    return false unless coluna

    agora = de_antes.fetch(coluna) { Carteira::Campos.guardado(apolice[coluna]) }
    return false unless agora == mudanca['depois']

    de_antes[coluna] = mudanca['antes']
    true
  end

  def subiu_a_origem?(apolice, passo)
    valores = passo.valores.to_h
    valores['origem_antes'].present? && apolice.origem == valores['origem_depois']
  end
end
