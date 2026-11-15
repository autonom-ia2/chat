# O lote de Trazer por PDFs como a tela lê (E6.3, #2899): enquanto lê, só o andamento; depois, o Conferir.
#
#   { id:, estado: 'lendo', total:, lidos: }
#   { id:, estado: 'lida' | 'trazendo' | 'trazida' | 'desfazendo' | 'desfeita', total:, lidos:,
#     seguros:, pessoas:, pessoasNovas:, porTipo: { 'auto' => 3, ... }, precisam:, recusados:, naoDeuParaLer:, fora:,
#     itens: [ ... ] }                                                       (Carteira::Trazer::Pdfs::ItemDoConferir)
#
# `seguros` são os PDFs prontos para entrar, e `pessoas`, de quantas pessoas (a mesma pessoa em dois PDFs conta uma
# vez). `precisam` são os PDFs que pedem algo à pessoa (o que falta ou o que conferir), e `itens` traz esses e os que
# não entram (não é apólice, não deu para ler, deixado de fora), para a pessoa saber de cada um. O PDF que esperou mais
# que o tempo limite na fila conta como "não deu para ler" (Carteira::LerItem::PRAZO), e a leitura deixa de estar
# "lendo" quando só sobram esses.
class Carteira::Trazer::Pdfs::Conferir
  def initialize(leitura)
    @leitura = leitura
    @pessoas = Carteira::Trazer::Pdfs::PessoaDoItem.new(leitura.account)
  end

  def call
    itens = @leitura.itens.order(:posicao).to_a
    lendo = itens.count { |item| lendo?(item) }
    base = { id: @leitura.id, estado: estado(lendo), total: @leitura.totais.to_h.fetch(Carteira::Leitura::DO_TRAZER, itens.size),
             lidos: itens.size - lendo }
    return base if base[:estado] == 'lendo'

    base.merge(numeros(itens.map { |item| vista(item) }))
  end

  # Os PDFs do lote no Conferir, cada um com a pessoa dele. Quem traz usa a mesma leitura.
  def vistas
    @leitura.itens.order(:posicao).map { |item| vista(item) }
  end

  private

  def lendo?(item)
    item.estado == 'lendo' && item.created_at >= Carteira::LerItem::PRAZO.ago
  end

  def estado(lendo)
    @leitura.estado == 'lendo' && lendo.zero? ? 'lida' : @leitura.estado
  end

  def vista(item)
    vista = Carteira::Trazer::Pdfs::ItemDoConferir.new(item)
    vista.lido? ? Carteira::Trazer::Pdfs::ItemDoConferir.new(item, pessoa: @pessoas.achar(vista.lido)) : vista
  end

  def numeros(vistas)
    prontos = vistas.select(&:pronto?)
    { seguros: prontos.size, pessoas: prontos.map(&:chave_da_pessoa).uniq.size, pessoasNovas: novas(prontos), porTipo: por_tipo(prontos),
      precisam: vistas.count(&:precisa?), recusados: com_estado(vistas, 'recusado'), naoDeuParaLer: nao_deu(vistas),
      fora: com_estado(vistas, 'fora'), itens: vistas.select(&:mostrar?).map(&:para_a_tela) }
  end

  def novas(prontos)
    prontos.reject(&:pessoa).map(&:chave_da_pessoa).uniq.size
  end

  def por_tipo(prontos)
    prontos.map { |vista| vista.lido.certo('tipo') }.tally
  end

  def com_estado(vistas, estado)
    vistas.count { |vista| vista.item.estado == estado }
  end

  # O que falhou e o que demorou demais na fila.
  def nao_deu(vistas)
    vistas.count { |vista| vista.item.estado == 'falhou' || (vista.item.estado == 'lendo' && !lendo?(vista.item)) }
  end
end
