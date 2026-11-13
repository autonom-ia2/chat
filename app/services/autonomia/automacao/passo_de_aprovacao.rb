# O passo "Pedir aprovação" (#2931): a automação para e pede a quem cuida do card, a uma pessoa ou a um time que aprove
# ou recuse antes de seguir. Exemplo: "desconto acima de 10% só sai com o OK da gerente".
#
# - Quem recebe: as pessoas da escolha (QuemDoPasso) que alcançam o registro agora, pela mesma pergunta do resto da
#   plataforma (PedidosDeAprovacao.ve_o_alvo?: o card pela CardPolicy, a conversa pela ConversationPolicy). Quem não vê o
#   card não recebe o pedido nem pode responder. Ninguém pode: segue na hora pelo "Se ninguém responder a tempo"
#   (`sem_quem_aprove`), com o motivo no histórico.
# - Onde chega: o sino (Notification `automacao_aprovacao`, só no painel, sem e-mail nem push) e a tela "Pedidos de
#   aprovação" (PedidosDeAprovacao), com a pergunta, o card ao lado e os botões Aprovar e Recusar. O pedido é o registro
#   do passo: guarda quem pode responder (`para`), o prazo (`ate`) e, depois, a decisão.
# - A pergunta é o texto do passo com os valores lidos na hora de mostrar, com as permissões de quem olha: o valor de
#   venda só para quem vê valores (decisão 9 do épico); para os outros, "valor oculto".
# - A resposta chega pelo painel, grava a decisão no pedido numa gravação só (a primeira vence) e acorda a execução pela
#   reserva da Escuta. No prazo sem resposta, o pedido fecha antes de seguir pelo galho: a resposta que chegar depois
#   é recusada no painel, e nunca muda o caminho que a automação já tomou.
class Autonomia::Automacao::PassoDeAprovacao
  Resultado = ::Autonomia::Automacao::PassoDeAcao::Resultado
  SEM_RESPOSTA = 'ninguem_respondeu'.freeze
  TIPO_DO_AVISO = 'automacao_aprovacao'.freeze

  def initialize(execucao:, passo:, alvo:, acesso: nil)
    @execucao = execucao
    @passo = passo
    @alvo = alvo
    @acesso = acesso
  end

  def perguntar
    para = ::Autonomia::Automacao::QuemDoPasso.pessoas(conta, @passo['quem'], contexto).select { |pessoa| alcanca?(pessoa) }
    return Resultado.new(tipo: :pulado, motivo: 'sem_quem_aprove', dados: { 'ramo' => SEM_RESPOSTA }) if para.empty?

    Resultado.new(tipo: :esperar, dados: { 'para' => para.map(&:id) })
  end

  # Com a espera gravada, o pedido aparece no sino de cada pessoa. O aviso que falhar não para os outros nem a espera.
  def depois_de_esperar(registro)
    conta.users.where(id: registro.dados['para']).find_each do |pessoa|
      Notification.create!(notification_type: TIPO_DO_AVISO, user: pessoa, account: conta, primary_actor: registro)
    rescue StandardError => e
      Rails.logger.error("[automacao][aprovacao] aviso não saiu registro=#{registro.id} user=#{pessoa.id} #{e.class}")
    end
  end

  def resposta(pedido, **)
    decisao = pedido.reload.dados['decisao']
    decisao ? decidida(decisao) : Resultado.new(tipo: :esperar, dados: {})
  end

  # No prazo: fecha o pedido se ninguém respondeu. A resposta que ganhou a corrida (gravada antes) vale.
  def fechar(pedido)
    fechou = ::Autonomia::Automacao::PedidosDeAprovacao.fechar(pedido)
    fechou ? nil : resposta(pedido).then { |lida| lida if lida.tipo == :ok }
  end

  # Quem recebe o pedido, para o ensaio: as pessoas que receberiam agora.
  def self.para(conta, passo, alvo) = new(execucao: nil, passo: passo, alvo: alvo).para_no_ensaio(conta)

  def para_no_ensaio(conta)
    @conta = conta
    ::Autonomia::Automacao::QuemDoPasso.pessoas(conta, @passo['quem'], contexto).select { |pessoa| alcanca?(pessoa) }
  end

  private

  def conta = @conta || @execucao.account

  def contexto = (@contexto ||= ::Autonomia::Automacao::Contexto.de(@alvo, execucao: @execucao))

  def alcanca?(pessoa) = ::Autonomia::Automacao::PedidosDeAprovacao.ve_o_alvo?(pessoa, @alvo)

  def decidida(decisao)
    ramo = decisao['aprovado'] ? 'aprovado' : 'recusado'
    Resultado.new(tipo: :ok, dados: { 'ramo' => ramo, 'por' => decisao['por'], 'por_nome' => decisao['por_nome'],
                                      'motivo_da_recusa' => decisao['motivo'] }.compact)
  end
end
