# Avisos no WhatsApp e gestão pelo cliente (#1192, F2-A): a reunião guarda se o cliente confirmou, quando parou os
# avisos e a conversa em que os avisos saem (a do convite, quando houver). Tabela do fork (crm_*), não do Chatwoot.
# Índice e FK da conversa ficam nas migrations seguintes (índice concorrente, FK sem validar e validação à parte).
class AddBookingNoticeFieldsToCrmMeetings < ActiveRecord::Migration[7.2]
  def change
    change_table :crm_meetings, bulk: true do |t|
      t.datetime :confirmed_at
      t.integer :confirmation_status, default: 0, null: false
      t.datetime :reminders_stopped_at
      t.bigint :conversation_id
    end
  end
end
