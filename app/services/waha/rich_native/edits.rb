# Edição de uma mensagem já gravada (chat#1709, fase 3), pelo cliente (volta do conector) ou pelo atendente (painel).
# O texto novo substitui o `content`; o anterior fica guardado em `content_attributes.edit_history`:
#   [{ "content" => "texto anterior", "edited_at" => ISO 8601, "by" => "contact" | "phone" } | { ..., "user_id" => 7 }]
# e `edited_at` marca a última edição (a bolha mostra "editada" e o histórico). Grava sob trava e sem as validações
# do modelo (a de rajada recusaria numa conversa movimentada); o `message_updated` leva a mudança à tela.
module Waha::RichNative::Edits
  HISTORY_KEY = 'edit_history'.freeze
  EDITED_AT_KEY = 'edited_at'.freeze

  module_function

  # author: { 'by' => 'contact' } ou { 'user_id' => 7 }. Devolve false quando o texto é o mesmo (nada a gravar).
  def apply!(message, content:, author:)
    message.with_lock do
      next false if message.content.to_s == content

      edited_at = Time.current.iso8601
      history = Array(message.content_attributes.to_h[HISTORY_KEY])
      history += [{ 'content' => message.content.to_s, 'edited_at' => edited_at }.merge(author)]
      message.content = content
      message.content_attributes = message.content_attributes.to_h.merge(HISTORY_KEY => history, EDITED_AT_KEY => edited_at)
      message.save!(validate: false)
    end
  end
end
