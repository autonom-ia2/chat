# FKs das colunas novas (#1192) sem validar as linhas existentes (todas nulas): não segura trava longa. A validação
# vem na migration seguinte. Conversa ou caixa apagada só desliga o vínculo; a reunião e a página continuam.
class AddBookingNoticeReferenceForeignKeys < ActiveRecord::Migration[7.2]
  def change
    add_foreign_key :crm_meetings, :conversations, column: :conversation_id, on_delete: :nullify, validate: false
    add_foreign_key :crm_agent_booking_profiles, :inboxes, column: :notice_inbox_id, on_delete: :nullify, validate: false
  end
end
