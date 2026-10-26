# O robô e a bolinha de não lida (#2202): o ÚNICO ponto da regra do robô em ConversaCanal::VistaAoResponder.
#
# DECISÃO PENDENTE DO RODRIGO: o robô apaga a bolinha? Hoje, sim (APAGA_A_BOLINHA). Para o robô não apagar mais nada,
# basta `APAGA_A_BOLINHA = false`: a resposta dele passa a não mexer no "visto", e o resto da regra segue igual.
#
# Quando apaga, vai só até onde o robô leu:
# - a mensagem do cliente que ele respondeu (`autonomia_reply_to_message_id`, gravado pelo agente nativo,
#   Autonomia::Agents::Operate::Responder#post_reply!). O que o cliente mandou enquanto a resposta era gerada continua
#   não lido;
# - sem essa marca (robô de integração, n8n), o momento do envio, como a resposta de uma pessoa;
# - nunca com a conversa esperando pessoa (bot_handoff_waiting?): o robô segue falando, mas quem precisa ver é a
#   equipe. É a mesma regra do waiting_since (Message#clear_waiting_since_on_outgoing_response, #1377). A resposta que
#   pede a passagem sai ANTES da passagem e marca até ela; o que o cliente manda depois fica não lido para a equipe.
module ConversaCanal::VistaAoResponder::Robo
  APAGA_A_BOLINHA = true
  REMETENTES = ::Messages::EnvioAutomatico::REMETENTES_AUTOMATICOS
  MARCA_DA_RESPONDIDA = 'autonomia_reply_to_message_id'.freeze

  module_function

  def robo?(message)
    REMETENTES.include?(message.sender_type)
  end

  # -> até onde o robô leu (Time, inclusive) ou nil, quando a resposta dele não marca nada.
  def ate_onde(message)
    return unless APAGA_A_BOLINHA
    return if message.conversation.bot_handoff_waiting?

    respondida(message)&.created_at || ::ConversaCanal::VistaAoResponder.antes_do_envio(message)
  end

  def respondida(message)
    id = message.content_attributes.to_h.with_indifferent_access[MARCA_DA_RESPONDIDA]
    return if id.blank?

    message.conversation.messages.where(account_id: message.account_id).incoming.find_by(id: id)
  end
end
