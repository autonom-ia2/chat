# "O que mudou" do PDF anexado a um seguro (E6.2, #2899): campo a campo, o que o PDF diz de diferente do que está
# guardado. Lê o item só pelo Carteira::ItemLido (decisão D1).
#
# - Campo que o PDF não trouxe ("não achei") nunca é mudança.
# - Campo igual ao guardado não aparece. O tipo `outro` não troca um tipo já decidido (é o "não sei" de quem
#   classifica o ramo, como no gravador: Carteira::Guardar::Mudancas).
# - Campo que o PDF trouxe sem certeza (o valor escrito sem "R$") aparece marcado como `confira` e nunca vem escolhido.
# - Campo corrigido à mão aparece com `corrigidoAMao` e não vem escolhido: fica o valor da pessoa, a menos que ela peça
#   o do PDF (decisão D3: aí ele recebe o valor e continua protegido).
# - Seguradora ou número diferentes aparecem como mudança comum, e a resposta leva `outraApolice: true`: o PDF pode ser
#   de outra apólice, e então NADA vem escolhido (decisão D2). A tela avisa antes.
# `usar` diz o que vem escolhido. Os valores saem como a tela lê: a data em AAAA-MM-DD e o valor em reais.
class Carteira::Pdf::OQueMudou
  OUTRO = 'outro'.freeze
  TIPO = 'tipo'.freeze
  DA_IDENTIDADE = { 'seguradora' => :seguradora, 'numero' => :numero }.freeze

  def initialize(apolice, item)
    @apolice = apolice
    @lido = Carteira::ItemLido.new(item)
  end

  def call
    linhas = Carteira::ItemLido::DA_TELA.filter_map { |campo, nome| linha(campo, nome) }
    outra = outra_apolice?
    { outraApolice: outra, mudancas: linhas.map { |linha| linha.merge(usar: !outra && linha[:usar]) } }
  end

  # { campo => valor na forma do banco } dos campos que o PDF diz diferente, para quem grava.
  def valores
    Carteira::ItemLido::DA_TELA.each_with_object({}) do |(campo, nome), achados|
      achados[campo] = no_pdf(nome) if muda?(campo, nome)
    end
  end

  private

  def linha(campo, nome)
    return unless muda?(campo, nome)

    corrigido = @apolice.corrigido_a_mao.include?(campo)
    confira = @lido.a_confirmar?(nome)
    { campo: campo, antes: para_a_tela(campo, guardado(campo)), noPdf: para_a_tela(campo, no_pdf(nome)), corrigidoAMao: corrigido,
      confira: confira, usar: !corrigido && !confira }
  end

  def muda?(campo, nome)
    return false if @lido.nao_achei?(nome)
    return false if campo == TIPO && no_pdf(nome) == OUTRO && @apolice.tipo.present?

    guardado(campo) != no_pdf(nome)
  end

  # A seguradora ou o número que o PDF trouxe não são os do seguro (comparados pela chave, sem espaço, caixa e acento).
  def outra_apolice?
    DA_IDENTIDADE.any? do |campo, coluna|
      nome = Carteira::ItemLido::DA_TELA.fetch(campo)
      !@lido.nao_achei?(nome) && Carteira::Chave.numero(no_pdf(nome)) != Carteira::Chave.numero(@apolice[coluna])
    end
  end

  def guardado(campo)
    Carteira::Campos.guardado(@apolice[Carteira::Campos::COLUNAS.fetch(campo)])
  end

  def no_pdf(nome)
    @lido.valor(nome)
  end

  def para_a_tela(campo, valor)
    campo == Carteira::Campos::VALOR ? Carteira::Campos.em_reais(valor) : valor
  end
end
