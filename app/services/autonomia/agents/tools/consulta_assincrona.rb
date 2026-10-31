# O ACEITE DE UMA FERRAMENTA HTTP ASSÍNCRONA (#1430), a cadastrada com tempo acima de `Tool::LIMIAR_ASSINCRONO`.
#
# Como na nativa assíncrona (`Bound#accept_async`), nada é chamado no turno: a execução abre em `pending`, o Responder
# a promove depois de a entrega do turno começar (`AsyncDispatcher`), e quem chama o sistema de fora é o
# `HttpAssincronaJob`. O que muda é o que a linha carrega: a ferramenta (o id, nunca o slug, que pode ser o de uma
# nativa), os argumentos JÁ TIPADOS (`ParamsTipados`, o mesmo que o síncrono manda) e a Idempotency-Key calculada
# AGORA, com o turno (`ChaveDeIdempotencia.para`): o job não tem turno, e a passada reenfileirada manda a mesma chave.
#
# O "mesmo pedido" é o resumo da ferramenta com os argumentos tipados: o mesmo pedido numa mensagem nova, com a consulta
# rodando, não abre outra (`ToolRun.abrir_ou_repetida`); outro pedido supersede a antiga. Nenhuma linha aqui lê a frase
# do cliente: quem decide pedir de novo é o modelo, e o código compara dados.
#
# Quem recusa é o `Bound` (`recusar`, o funil único das recusas em JSON); aqui se monta, se abre e se registra a repetição.
class Autonomia::Agents::Tools::ConsultaAssincrona
  ToolRun = ::Autonomia::Agents::ToolRun

  # O que o modelo lê no aceite: neutro, sem prometer prazo, para ele avisar o cliente na mesma resposta.
  ACEITE = 'Consulta iniciada. Avise o cliente que você está consultando e que responde assim que tiver o resultado.'.freeze
  # O mesmo pedido, numa mensagem nova, com a consulta ainda rodando: nada abre.
  JA_CONSULTANDO = 'Esta mesma consulta já está em andamento, com os mesmos dados. Não abri outra. Diga ao cliente que ' \
                   'você já está consultando e que responde assim que tiver o resultado.'.freeze

  def initialize(tool:, agent:, delivery:, args:)
    @tool = tool
    @agent = agent
    @delivery = delivery
    # Levanta `HttpExecutor::ValorRecusado` quando um valor não converte: o `Bound` recusa como no síncrono.
    @params = ::Autonomia::Agents::Tools::ParamsTipados.converter(args.to_h.deep_stringify_keys, tool.param_schema)
  end

  def faixa
    ToolRun::FAIXA_DA_CONSULTA
  end

  # A identidade do pedido: a ferramenta e os argumentos tipados, em ordem. Não leva conversa nem turno: compara
  # pedidos da mesma conversa.
  def pedido
    @pedido ||= ::Autonomia::Agents::Tools::ChaveDeIdempotencia.resumo([@tool.id, ::Autonomia::Agents::Tools::ChaveDeIdempotencia.em_ordem(@params)])
  end

  # -> [execução aberta, nil], [nil, execução repetida] ou [nil, nil] (o índice único recusou).
  def abrir
    ToolRun.abrir_ou_repetida(
      agent: @agent, slug: @tool.slug, arguments: @params, pedido: pedido,
      marcas: { ToolRun::CHAVE_DA_CONSULTA => chave },
      scope: { conversation_id: @delivery.conversation.id, agent_inbox_id: @delivery.agent_inbox&.id,
               origin_message_id: @delivery.origin_message_id, faixa: faixa, autonomia_agent_tool_id: @tool.id }
    )
  end

  # O mesmo pedido com a consulta rodando: registrado como a repetição da nativa (entrega 6), com o texto neutro.
  def em_andamento
    ::Autonomia::Agents::Tools::Recusa.registrar(
      ::Autonomia::Agents::Tools::PedidoRepetido::MOTIVO, slug: @tool.slug, agente: @agent, onde: 'aceite',
                                                          conversa: ::Autonomia::Agents::Tools::Recusa.conversa_de(@delivery)
    )
    JA_CONSULTANDO
  end

  private

  def chave
    ::Autonomia::Agents::Tools::ChaveDeIdempotencia.para(tool: @tool, turno: @delivery, params: @params)
  end
end
