# Edição de uma mensagem já gravada (chat#1709; formato da tela do Frontend geral, #1702), pelo cliente (volta do
# conector), pelo celular da empresa ou pelo atendente (painel). O texto novo substitui o `content`; o anterior fica em
#   content_attributes.edit_history = [{ "content" => "texto anterior", "edited_at" => ISO 8601,
#                                        "sender_type" => "Contact" | "User", "sender_id" => 12 | nil }]
# do mais antigo para o mais novo, e `edited_at` marca a última edição. Autor: Contact + contact_id (o cliente);
# User + user.id (atendente pelo painel); User + nil (celular da empresa). O histórico guarda as HISTORY_LIMIT edições
# mais recentes; o texto tem o teto do WhatsApp (MAX_LENGTH, o mesmo do painel em messageActions.js). Grava sob trava e
# sem as validações do modelo (a de rajada recusaria numa conversa movimentada); o `message_updated` leva a mudança à
# tela.
module Waha::RichNative::Edits
  HISTORY_KEY = 'edit_history'.freeze
  EDITED_AT_KEY = 'edited_at'.freeze
  # Teto do texto do WhatsApp; o painel usa o mesmo (EDIT_MAX_LENGTH em messageActions.js).
  MAX_LENGTH = 4096
  HISTORY_LIMIT = 10

  module_function

  def valid_text?(text)
    text.is_a?(String) && text.strip.present? && text.length <= MAX_LENGTH
  end

  def contact_author(contact_id)
    { 'sender_type' => 'Contact', 'sender_id' => contact_id }
  end

  # `user_id` nil: o celular da empresa.
  def user_author(user_id = nil)
    { 'sender_type' => 'User', 'sender_id' => user_id }
  end

  # author: contact_author ou user_author. timestamp: a hora da edição no WhatsApp (segundos, `waha_edit.timestamp` do
  # conector c2y-rich-5), quando veio. Devolve false quando o texto é o mesmo ou a edição chegou fora de ordem (mais velha
  # que a última guardada, Waha::RichNative::EventTime.replaces?): nada a gravar.
  def apply!(message, content:, author:, timestamp: nil)
    message.with_lock do
      next false if message.content.to_s == content || out_of_order?(message, timestamp)

      edited_at = Waha::RichNative::EventTime.iso8601(timestamp)
      history = Array(message.content_attributes.to_h[HISTORY_KEY])
      history = (history + [{ 'content' => message.content.to_s, 'edited_at' => edited_at }.merge(author)]).last(HISTORY_LIMIT)
      message.content = content
      message.content_attributes = message.content_attributes.to_h.merge(HISTORY_KEY => history, EDITED_AT_KEY => edited_at)
      message.save!(validate: false)
    end
  end

  # Sem a hora do WhatsApp (edição pelo painel, conector antigo), a ordem de chegada vale, como antes.
  def out_of_order?(message, timestamp)
    return false if Waha::RichNative::EventTime.at(timestamp).nil?

    !Waha::RichNative::EventTime.replaces?(Waha::RichNative::EventTime.iso8601(timestamp), message.content_attributes.to_h[EDITED_AT_KEY])
  end
end
