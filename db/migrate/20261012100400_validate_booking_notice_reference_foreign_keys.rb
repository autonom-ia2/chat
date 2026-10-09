# Valida as FKs criadas sem validação na migration anterior (#1192). Só lê; não bloqueia escrita. Desfazer não tem o
# que fazer: a FK continua (quem a remove é o desfazer da migration anterior).
class ValidateBookingNoticeReferenceForeignKeys < ActiveRecord::Migration[7.2]
  def up
    validate_foreign_key :crm_meetings, :conversations, column: :conversation_id
    validate_foreign_key :crm_agent_booking_profiles, :inboxes, column: :notice_inbox_id
  end

  def down; end
end
