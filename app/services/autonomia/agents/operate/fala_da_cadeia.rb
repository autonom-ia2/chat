# A FALA NA CADEIA DE PEDAÇOS (#3211). O que a paridade da conversa muda no ChunkedDeliveryJob, num lugar só (o job já
# está no teto de tamanho). Tudo por opção do agente (ParidadeDaConversa); desligadas, nada aqui age.
#
# - `comecada?` (P3, `conversa_entrega_inteira` + fila): do 2º pedaço em diante a fala já começou e mensagem nova não a
#   corta; o job deixa de conferir o turno. O 1º pedaço sempre confere.
# - `renovar` (P2, `conversa_em_fila`): a fala continua no próximo pedaço; renova a marca de quem fala (FalaEmCurso),
#   só se é deste turno.
# - `parou` (P1, `conversa_espera_a_fala`): a cadeia parou antes do 1º pedaço sem postá-lo (mensagem nova, troca de dono,
#   pessoa assumiu). Não houve fala, e o fim previsto que o Responder gravou faria a rajada seguinte esperar por nada:
#   apaga só o fim deste turno (FalaEmCurso.esquecer_o_fim, compare-and-delete). O bloco diz se o 1º pedaço já foi
#   postado (o retry de um pedaço que entrou não apaga: a fala aconteceu); só é chamado com a opção ligada.
module Autonomia::Agents::Operate::FalaDaCadeia
  module_function

  def comecada?(agent, index)
    index.positive? && ::Autonomia::Agents::ParidadeDaConversa.entrega_inteira?(agent)
  end

  def renovar(conversation_id, agent, message_id)
    return unless ::Autonomia::Agents::ParidadeDaConversa.em_fila?(agent)

    ::Autonomia::Agents::Operate::FalaEmCurso.renovar(conversation_id, message_id)
  end

  def parou(conversation_id, agent, message_id, index)
    return unless index.zero? && ::Autonomia::Agents::ParidadeDaConversa.espera_a_fala?(agent)
    return if yield

    ::Autonomia::Agents::Operate::FalaEmCurso.esquecer_o_fim(conversation_id, message_id)
  end
end
