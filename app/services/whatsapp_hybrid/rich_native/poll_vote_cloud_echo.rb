# Prepend em Whatsapp::IncomingMessageBaseService (chat#1709, fase 3): numa caixa híbrida com a flag
# `whatsapp_rich_native`, o `unsupported` que a Meta entrega à Cloud em resposta a uma enquete NOSSA do plano B não vira
# bolha "não suportada". No número em coexistência, o voto do cliente também pode chegar à Cloud como mensagem que ela
# não sabe mostrar (a confirmar em aparelho, teste real 9 do contrato); o voto de verdade já volta pelo motor
# (WhatsappHybrid::RichNative::PollVoteJob), e a bolha a mais faria a IA responder duas vezes.
# Só quando o `context.id` do `unsupported` aponta uma enquete nativa nossa da caixa (pelo `source_id` ou pelo id físico
# de dentro do wamid, WhatsappHybrid::RichNative::PollLookup). Qualquer outro `unsupported`: o fluxo de sempre.
module WhatsappHybrid::RichNative::PollVoteCloudEcho
  private

  def create_unsupported_message(message)
    return super unless poll_vote_echo?(message)

    Rails.logger.info("[whatsapp_hybrid] cloud unsupported for our poll skipped inbox=#{@inbox.id}")
  end

  def poll_vote_echo?(message)
    context_id = message['context']&.[]('id').to_s
    return false if context_id.blank? || outgoing_echo
    return false unless WhatsappHybrid::RichNative.hybrid?(@inbox) && Waha::RichNative.enabled?(@inbox.account)

    poll_by_context(context_id).present?
  rescue StandardError => e
    Rails.logger.error("[whatsapp_hybrid] poll vote cloud echo inbox=#{@inbox.id} #{e.class}")
    false
  end

  def poll_by_context(context_id)
    direct = Message.find_by(inbox_id: @inbox.id, message_type: :outgoing, source_id: context_id)
    return direct if Waha::RichNative::PollVote.native_poll?(direct)

    WhatsappHybrid::RichNative::PollLookup.find(@inbox.id, WhatsappHybrid::Wamid.message_id(context_id))
  end
end
