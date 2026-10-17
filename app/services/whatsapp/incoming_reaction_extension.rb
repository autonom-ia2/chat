# Prepend em Whatsapp::IncomingMessageBaseService (#1702): a reação do cliente vira o selo na mensagem reagida
# (Whatsapp::ReactionRecorder). Vale para a Cloud API, o 360dialog e a caixa híbrida, que recebem pelo mesmo serviço.
#
# O caminho do agente da Autonomia continua igual e roda PRIMEIRO (`super`): com agente na caixa, a reação ainda vira
# a mensagem sintética que ele lê (ReactionMaterializer, com a trava do canal pela chave do evento). O selo não usa
# essa trava nem cria mensagem com o id do evento; grava só na mensagem reagida. Um caminho não derruba o outro.
# Só com a chave `conversa_cara_do_canal`; desligada, a reação segue descartada como no Chatwoot.
module Whatsapp::IncomingReactionExtension
  private

  def process_messages
    return super unless customer_reaction?

    result = super
    record_customer_reaction
    result
  end

  def customer_reaction?
    !outgoing_echo && messages_data.present? && message_type == 'reaction' && ConversaCanal::Pele.ligada?(inbox.account)
  end

  def record_customer_reaction
    data = messages_data.first
    reaction = data[:reaction] || {}
    Whatsapp::ReactionRecorder.new(
      inbox: inbox, reacted_source_id: reaction[:message_id], emoji: reaction[:emoji], reacted_at: reaction_time(data)
    ).perform
  rescue StandardError => e
    Rails.logger.warn("[whatsapp][reaction] record failed inbox=#{inbox.id} #{e.class}")
    ChatwootExceptionTracker.new(e, account: inbox.account).capture_exception
    nil
  end

  def reaction_time(data)
    seconds = data[:timestamp].to_i
    seconds.positive? ? Time.zone.at(seconds) : nil
  end
end
