# `waha_poll_vote` (chat#1709, fase 3): o voto do cliente numa enquete nativa nossa vira a resposta à enquete
# (Waha::RichNative::PollVote: `selected_option`, `selected_options` e `in_reply_to`). O conector só cria o voto de
# enquete com o id determinístico nosso; mesmo assim, aqui a enquete é conferida de novo (mensagem de saída `poll`,
# nativa, na mesma conversa e caixa) e cada título precisa ser de uma opção oferecida. Sem isso, fica o texto comum.
module Waha::RichNative::Inbound::PollVote
  module_function

  def apply(message, data)
    return unless message.incoming? && data.is_a?(Hash)

    poll = Waha::RichNative::PollVote.poll_for(data['poll_message_id'], conversation_id: message.conversation_id, inbox_id: message.inbox_id)
    return if poll.nil?

    selected = Waha::RichNative::PollVote.selected_for(poll, data['options'])
    Waha::RichNative::PollVote.assign!(message, poll, selected) if selected
  end
end
