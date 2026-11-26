# A FALA NA CADEIA DE PEDAÇOS (#3211). O que a paridade da conversa muda no ChunkedDeliveryJob, num lugar só (o job já
# está no teto de tamanho). Tudo por opção do agente (ParidadeDaConversa, ligadas por padrão menos na Lia); com elas
# desligadas, nada aqui age.
#
# - `comecada?` (P3, `conversa_entrega_inteira` + fila): do 2º pedaço em diante a fala já começou e mensagem nova não a
#   corta; o job deixa de conferir o turno. O 1º pedaço sempre confere.
# - `renovar` (P2, `conversa_em_fila`): a fala continua no próximo pedaço; renova a marca de quem fala (FalaEmCurso),
#   só se é deste turno.
# - `acabou` (P1, `conversa_espera_a_fala`): a fala deste turno acabou, porque o último pedaço saiu ou porque a cadeia
#   parou em qualquer pedaço (mensagem nova, troca de dono, pessoa assumiu, retry de um pedaço que já entrou). Os pedaços
#   que faltavam não vão sair, e o fim previsto que o Responder gravou faria a rajada seguinte esperar por eles: apaga só
#   o fim deste turno (FalaEmCurso.esquecer_o_fim, compare-and-delete; o fim de um turno mais novo fica). #3235: antes
#   só a parada antes do 1º pedaço apagava, e o fim ficava até passar.
module Autonomia::Agents::Operate::FalaDaCadeia
  module_function

  def comecada?(agent, inbox, index)
    index.positive? && ::Autonomia::Agents::ParidadeDaConversa.entrega_inteira?(agent, inbox)
  end

  def renovar(conversation, agent, message_id)
    return unless ::Autonomia::Agents::ParidadeDaConversa.em_fila?(agent, conversation.inbox)

    ::Autonomia::Agents::Operate::FalaEmCurso.renovar(conversation.id, message_id)
  end

  def acabou(conversation, agent, message_id)
    return unless ::Autonomia::Agents::ParidadeDaConversa.espera_a_fala?(agent, conversation.inbox)

    ::Autonomia::Agents::Operate::FalaEmCurso.esquecer_o_fim(conversation.id, message_id)
  end
end
