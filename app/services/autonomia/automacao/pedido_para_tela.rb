# Um pedido de aprovação (#2931) como a tela "Pedidos de aprovação" mostra para quem olha (`account_user`): a pergunta
# com os valores lidos agora, com as permissões dessa pessoa (o valor de venda só para quem vê valores, decisão 9; para
# os outros, "valor oculto"), o prazo, a automação, o card ao lado (sem o valor para quem não vê valores) e, já
# respondido, quem respondeu, a decisão e o motivo.
class Autonomia::Automacao::PedidoParaTela
  def initialize(pedido, account_user)
    @pedido = pedido
    @account_user = account_user
    @execucao = pedido.execucao
    @contexto = ::Autonomia::Automacao::Contexto.de(@execucao.alvo, execucao: @execucao)
  end

  def resultado
    {
      id: @pedido.id, estado: estado, pergunta: pergunta, ate: @pedido.dados['ate'], criado_em: @pedido.created_at,
      automacao: { id: @execucao.automacao_id, nome: @execucao.automacao.nome },
      decisao: decisao, card: card, conversa_id: conversa_id
    }.compact
  end

  private

  def estado
    return @pedido.dados.dig('decisao', 'aprovado') ? 'aprovado' : 'recusado' if @pedido.dados['decisao']

    ::Autonomia::Automacao::PedidosDeAprovacao.aberto?(@pedido) ? 'aberto' : 'encerrado'
  end

  def decisao
    lida = @pedido.dados['decisao']
    lida && { por_nome: lida['por_nome'], por_mim: lida['por'] == @account_user.user_id, em: lida['em'], motivo: lida['motivo'] }.compact
  end

  # O texto do passo na versão em que a execução entrou, com os valores de agora.
  def pergunta
    passo = ::Autonomia::Automacao::Roteiro.new(@execucao.versao.receita).passo(@pedido.passo).to_h
    Array(passo['pergunta']).map { |parte| parte.is_a?(Hash) ? valor(parte['$valor']) : parte.to_s }.join.squish
  end

  def valor(caminho)
    return I18n.t('autonomia.automacao.pedido.valor_oculto') unless ::Autonomia::Automacao::Valores.pode_ler?(caminho, @account_user)

    lido = valores.ler(caminho)
    lido.is_a?(Array) ? lido.join(', ') : lido.to_s
  end

  def valores = (@valores ||= ::Autonomia::Automacao::Valores.new(alvo: @contexto, quem: @account_user.user))

  # O card no formato do cartão do funil (CrmKanbanCard).
  def card
    card = @contexto.card
    return unless card

    { id: card.id, title: card.title, currency: card.currency, contact: card.contact&.slice(:id, :name),
      responsible: card.owner && { type: 'agent', name: card.owner.name },
      value_cents: (card.value_cents if ::Autonomia::Automacao::Valores.pode_ler?(::Autonomia::Automacao::ComIa::VALOR, @account_user)) }.compact
  end

  def conversa_id
    conversa = @contexto.conversa
    conversa.display_id if conversa && ::Autonomia::Automacao::PedidosDeAprovacao.ve_o_alvo?(@account_user.user, conversa)
  end
end
