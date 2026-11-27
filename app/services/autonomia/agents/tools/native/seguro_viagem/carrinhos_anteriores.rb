# OS CARRINHOS ANTERIORES DE UMA COMPRA do Seguro Viagem (#3263, #3266): o que uma chamada de
# `gerar_proposta_seguro_viagem` cancelou antes de comprar, guardado do começo ao fim dela. Fora da ferramenta só pelo
# tamanho dela (ClassLength).
#
#   - `liberar!`, sob o lock da cotação, antes da compra: o carrinho desta cotação e os das outras cotações da mesma
#     viagem (`OutrasDaMesmaViagem.com_carrinho`) passam por `CarrinhoAnterior.liberar!`;
#   - `da_compra`: a cotação e os carrinhos anteriores que a nota do 400 da compra cita (#3265);
#   - `nao_liberado`: `liberar!` levantou; um cancelamento que falha depois de outro já feito segue como abaixo;
#   - `compra_nao_saiu`: a compra nova não saiu (erro, sem link, ou um cancelamento seguinte que falhou) depois de algum
#     cancelamento: a nota, a marca desta cotação (`CarrinhoAnterior.compra_nao_saiu`) e a das outras;
#   - `marcar_outras`: na compra que saiu, a marca de cancelada nas outras cotações canceladas.
#
# A marca das outras sai DEPOIS da transação da compra (o erro dela desfaz a transação; o cancelamento na Universal não
# volta atrás), chamada por quem sabe que algo foi cancelado, nunca num `ensure`.
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

  # -> o que `Falhas.tratar_compra` usa na nota: a cotação (a chave) e os números dos carrinhos anteriores desta conversa
  # que esta compra conhece (os das outras cotações canceladas e o da proposta guardada nesta cotação; lista vazia sem
  # nenhum).
  def da_compra
    { cotacao_id: @cotacao.id, carrinhos: [*@outras.map(&:last), SeguroViagem::Pagamento.carrinho(@cotacao)].compact.uniq }
  end

  # -> o texto ao modelo quando `liberar!` levantou (`CarrinhoAnterior::NAO_SAIU`). Um cancelamento que falha depois de
  # outro já feito (#3266) não é só a falha: o link anterior morreu (`compra_nao_saiu`).
  def nao_liberado(motivo, acao:, agent:, conversation:)
    compra_nao_saiu(SeguroViagem::CarrinhoAnterior.tratar(motivo, acao: acao, agent: agent, conversation: conversation))
  end

  # -> o texto ao modelo. Sem nada cancelado nesta chamada, `texto` como veio.
  def compra_nao_saiu(texto, compra: nil)
    cancelados = [*@outras.map(&:last), @cancelado].compact
    return texto if cancelados.empty?

    aviso = SeguroViagem::CarrinhoAnterior.compra_nao_saiu(@cotacao, @cancelado, texto, cancelados: cancelados, compra: compra)
    marcar_outras
    aviso
  end

  def marcar_outras
    SeguroViagem::OutrasDaMesmaViagem.marcar_canceladas(@outras)
  end
end
