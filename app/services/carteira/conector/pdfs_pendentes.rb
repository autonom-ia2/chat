# Os registros de uma busca no conector cujo PDF ainda falta baixar, e as tentativas de cada um (#3175), para
# Carteira::Conector::BaixarPdf. Sem coluna nova: o andamento fica nos `campos` do item, pelo Carteira::ItemLido.
#
# Entram os registros com `pdf_ref` que:
# - viraram seguro nesta busca (`trazido`, com `apolice`); ou
# - não mudaram nada num seguro que já estava na carteira (`igual`, sem `apolice`: Carteira::Conector::Gravar). O seguro
#   é o da mesma referência e do mesmo termo (Carteira::Conector::PessoaDoRegistro#seguro_da_referencia). É por aqui que
#   o PDF que falhou numa busca volta a ser tentado na busca do dia seguinte.
#
# Marcas no item (nomes nossos; valores sem dado de cliente):
# - `pdf_tentado_em`: a última tentativa. Quem falhou espera ESPERA para a próxima, na mesma busca;
# - `pdf_tentativas`: quantas vezes este registro tentou;
# - `pdf_motivo`: o código da última falha (Carteira::Conector::PdfDoZip::Recusa, `nao_e_pdf` ou a classe do erro);
# - `pdf_apolice`: o id do seguro a que o PDF se destina (o `igual` não tem `apolice`);
# - `pdf_fim`: o registro saiu da fila: `baixado`, `ja_tinha` (o seguro já tem PDF), `sem_seguro` (o `igual` cujo seguro
#   não foi achado) ou `desistiu`.
#
# O teto de tentativas é POR SEGURO, somando todas as buscas da conta que ainda guardam os itens (TETO_DE_TENTATIVAS):
# o documento que nunca vem não é pedido ao portal todo dia, para sempre. O item de antes desta regra, marcado como
# tentado sem contagem, conta como uma tentativa.
class Carteira::Conector::PdfsPendentes
  TENTADO = 'pdf_tentado_em'.freeze
  TENTATIVAS = 'pdf_tentativas'.freeze
  MOTIVO = 'pdf_motivo'.freeze
  APOLICE = 'pdf_apolice'.freeze
  FIM = 'pdf_fim'.freeze
  BAIXADO = 'baixado'.freeze
  JA_TINHA = 'ja_tinha'.freeze
  SEM_SEGURO = 'sem_seguro'.freeze
  DESISTIU = 'desistiu'.freeze
  TETO_DE_TENTATIVAS = 3
  ESPERA = 1.hour
  ESTADOS = %w[trazido igual].freeze
  CAMPO = 'carteira_leitura_itens.campos ->> ?'.freeze
  SOMA_DAS_TENTATIVAS = Arel.sql("COALESCE((carteira_leitura_itens.campos ->> 'pdf_tentativas')::int, 1)")

  def initialize(leitura)
    @leitura = leitura
    @pessoas = Carteira::Conector::PessoaDoRegistro.new(leitura.account)
  end

  # Os que podem tentar agora: os que nunca tentaram e os que falharam há mais de ESPERA.
  def agora
    na_fila.where("#{CAMPO} IS NULL OR (#{CAMPO})::timestamptz <= ?", TENTADO, TENTADO, ESPERA.ago)
  end

  # Sobrou quem falhou e ainda vai tentar de novo, depois da espera.
  def mais_tarde?
    na_fila.where("#{CAMPO} IS NOT NULL", TENTADO).exists?
  end

  # O seguro do registro, ou nil.
  def apolice_de(item)
    return item.apolice if item.apolice_id

    @pessoas.seguro_da_referencia(Carteira::ItemLido.new(item))
  end

  def cabe_tentar?(apolice)
    tentativas_do_seguro(apolice) < TETO_DE_TENTATIVAS
  end

  # A contagem vai junto, mesmo zerada: o item marcado sem ela contaria como uma tentativa (o de antes desta regra).
  def terminar(item, apolice, fim)
    marcar(item, apolice, FIM => fim, TENTATIVAS => Carteira::ItemLido.new(item).valor(TENTATIVAS).to_i)
  end

  # A falha conta uma tentativa; no teto do seguro, o registro sai da fila. Sem seguro (o erro veio antes de achá-lo),
  # conta só o registro: um erro de passagem não é desistência.
  def falhou(item, apolice, motivo)
    tentativas = Carteira::ItemLido.new(item).valor(TENTATIVAS).to_i + 1
    do_seguro = apolice ? tentativas_do_seguro(apolice, sem: item) : 0
    no_teto = do_seguro + tentativas >= TETO_DE_TENTATIVAS
    marcar(item, apolice, { TENTATIVAS => tentativas, MOTIVO => motivo, FIM => (DESISTIU if no_teto) })
  end

  private

  def na_fila
    @leitura.itens.where(estado: ESTADOS).where("#{CAMPO} IS NOT NULL", 'pdf_ref').where("#{CAMPO} IS NULL", FIM)
            .where("carteira_leitura_itens.estado = 'igual' OR carteira_leitura_itens.apolice_id IS NOT NULL").order(:posicao)
  end

  def tentativas_do_seguro(apolice, sem: nil)
    Carteira::LeituraItem.where(account_id: @leitura.account_id).where.not(id: sem&.id)
                         .where("carteira_leitura_itens.apolice_id = :id OR carteira_leitura_itens.campos ->> :chave = :texto",
                                id: apolice.id, chave: APOLICE, texto: apolice.id.to_s)
                         .where("#{CAMPO} IS NOT NULL", TENTADO).sum(SOMA_DAS_TENTATIVAS)
  end

  # Sem seguro (o erro veio antes de achá-lo), o vínculo que o item já tinha fica: as tentativas seguem contando no teto.
  def marcar(item, apolice, valores)
    valores = valores.merge(TENTADO => Time.current.iso8601)
    valores = valores.merge(APOLICE => apolice.id) if apolice
    item.update!(Carteira::ItemLido.new(item).com(valores))
  end
end
