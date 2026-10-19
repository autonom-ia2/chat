# `waha_poll_vote` (chat#1709, fase 3): o voto do cliente numa enquete nativa nossa fica agregado na enquete
# (`poll_votes`, Waha::RichNative::PollVotes) e a mensagem do voto vira atividade escondida (`poll_vote_applied_to`),
# como a reação. O conector só cria o voto de enquete com o id determinístico nosso; mesmo assim, aqui a enquete é
# conferida de novo (mensagem de saída `poll`, nativa, na mesma conversa e caixa) e cada título precisa ser de uma
# opção oferecida. Sem isso, fica o texto comum.
module Waha::RichNative::Inbound::PollVote
  module_function

  def apply(message, data)
    return unless message.incoming? && data.is_a?(Hash)
    # Em grupo o voto não é agregado (todos seriam o mesmo eleitor): fica o texto do conector, visível.
    return if Waha::RichNative.group_conversation?(message.conversation)

    poll = Waha::RichNative::PollVote.poll_for(data['poll_message_id'], conversation_id: message.conversation_id, inbox_id: message.inbox_id)
    return if poll.nil?

    selected = Waha::RichNative::PollVote.selected_for(poll, data['options'])
    Waha::RichNative::PollVote.record_vote!(message, poll, selected, timestamp: data['timestamp']) if selected
  end
end
