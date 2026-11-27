# OS CARRINHOS ANTERIORES DE UMA COMPRA do Seguro Viagem (#3263, #3266): o que uma chamada de
# `gerar_proposta_seguro_viagem` cancelou antes de comprar, guardado do começo ao fim dela. Fora da ferramenta só pelo
# tamanho dela (ClassLength).
#
#   - `liberar!`, sob o lock da cotação, antes da compra: o carrinho desta cotação e os das outras cotações da mesma
#     viagem (`OutrasDaMesmaViagem.com_carrinho`) passam por `CarrinhoAnterior.liberar!`;
#   - `numeros`: os carrinhos anteriores que a nota do 400 da compra cita (#3265);
#   - `compra_nao_saiu`: a compra nova falhou depois de algum cancelamento (`CarrinhoAnterior.compra_nao_saiu`);
#   - `marcar_outras`: depois da compra, saindo ou não, a marca de cancelada nas outras cotações canceladas.
class Autonomia::Agents::Tools::Native::SeguroViagem::CarrinhosAnteriores
  SeguroViagem = Autonomia::Agents::Tools::Native::SeguroViagem

  def initialize(cotacao, agent)
    @cotacao = cotacao
    @agent = agent
    @cancelado = nil
    @outras = []
  end

  # Levanta o que `CarrinhoAnterior.liberar!` levanta. Cada outra cotação cancelada entra em `@outras` na hora, mesmo que
  # um cancelamento seguinte falhe.
  def liberar!(cliente)
    outras = SeguroViagem::OutrasDaMesmaViagem.com_carrinho(@cotacao, @agent)
    @cancelado = SeguroViagem::CarrinhoAnterior.liberar!(@cotacao, cliente, outras, ->(par) { @outras << par })
  end

  # -> os números dos carrinhos anteriores desta conversa que esta compra conhece: os das outras cotações canceladas e o
  # da proposta guardada nesta cotação. Lista vazia sem nenhum.
  def numeros
    [*@outras.map(&:last), SeguroViagem::Pagamento.carrinho(@cotacao)].compact.uniq
  end

  # -> o texto ao modelo. Sem nada cancelado nesta chamada, `texto` como veio.
  def compra_nao_saiu(texto, conversation:, compra:)
    return texto if @cancelado.nil? && @outras.empty?

    SeguroViagem::CarrinhoAnterior.compra_nao_saiu(@cotacao, @cancelado, texto, conversation: conversation, compra: compra)
  end

  def marcar_outras
    SeguroViagem::OutrasDaMesmaViagem.marcar_canceladas(@outras)
  end
end
