# O voto numa enquete nativa nossa (chat#1709, fase 3), comum à caixa WAHA comum (Waha::RichNative::Inbound, chave
# `waha_poll_vote` do conector) e ao plano B do Híbrido (WhatsappHybrid::RichNative::PollVoteJob, evento `poll.vote`).
# O motor devolve os TÍTULOS das opções marcadas: cada um vira a opção oferecida de título IGUAL (comparação exata).
# Grava na mensagem do voto, que é a resposta à enquete:
#   in_reply_to       = a enquete;
#   selected_options  = [{ id, title }, ...] (todas as marcadas; vazio = voto retirado);
#   selected_option   = a primeira (o mesmo campo da escolha de lista, que o robô e a bolha já leem).
# Voto retirado (nenhuma marcada) vira atividade escondida (`c2y_hidden`): a bolha da enquete volta a "sem voto" e a IA
# não responde. A enquete precisa ser NOSSA: mensagem de saída `poll` que saiu nativa, na mesma conversa e caixa.
module Waha::RichNative::PollVote
  TYPE = 'poll'.freeze

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

  # Grava o voto na mensagem que está sendo criada (antes do INSERT).
  def assign!(message, poll, selected)
    attributes = message.content_attributes.to_h.merge('in_reply_to' => poll.id, 'selected_options' => selected)
    if selected.empty?
      message.message_type = :activity
      message.private = false
      attributes = attributes.except('selected_option').merge('c2y_hidden' => true)
    else
      attributes['selected_option'] = selected.first
    end
    message.content_attributes = attributes
  end
end
