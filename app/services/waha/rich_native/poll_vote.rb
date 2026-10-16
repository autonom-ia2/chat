# O voto numa enquete nativa nossa (chat#1709, fase 3), comum à caixa WAHA comum (Waha::RichNative::Inbound, chave
# `waha_poll_vote` do conector) e ao plano B do Híbrido (WhatsappHybrid::RichNative::PollVoteJob, evento `poll.vote`).
# O motor devolve os TÍTULOS das opções marcadas: cada um vira a opção oferecida de título IGUAL (comparação exata).
# A enquete precisa ser NOSSA: mensagem de saída `poll` que saiu nativa, na mesma conversa e caixa. O voto fica
# agregado na enquete (Waha::RichNative::PollVotes); a mensagem do voto vira atividade escondida (`record_vote!`).
module Waha::RichNative::PollVote
  TYPE = 'poll'.freeze
  HIDDEN_KIND = 'poll_vote'.freeze
  APPLIED_KEY = 'poll_vote_applied_to'.freeze

  module_function

  # A enquete nossa que confere, ou nil.
  def poll_for(message_id, conversation_id:, inbox_id:)
    poll = Message.find_by(id: message_id, conversation_id: conversation_id, inbox_id: inbox_id, message_type: :outgoing)
    poll if native_poll?(poll)
  end

  def native_poll?(message)
    return false if message.nil?

    rich = message.content_attributes.to_h[RichMessages::KEY]
    rich.is_a?(Hash) && rich['type'] == TYPE && Waha::RichNative.sent_native?(message)
  end

  # [{ 'id', 'title' }] das opções marcadas, ou nil quando algum título não é de uma opção oferecida.
  def selected_for(poll, titles)
    offered = Array(poll.content_attributes.to_h.dig(RichMessages::KEY, 'options')).select { |option| option.is_a?(Hash) }
    titles = Array(titles)
    selected = titles.filter_map do |title|
      option = offered.find { |candidate| title.is_a?(String) && candidate['title'] == title }
      { 'id' => option['id'], 'title' => option['title'] } if option
    end
    selected if selected.size == titles.size
  end

  # Grava o voto na enquete e transforma a mensagem do voto (ainda não gravada) em atividade escondida.
  def record_vote!(message, poll, selected)
    Waha::RichNative::PollVotes.apply!(poll, sender: poll.conversation.contact, titles: selected.pluck('title'))
    Waha::RichNative::Inbound.hide!(message, HIDDEN_KIND, APPLIED_KEY => poll.id)
  end
end
