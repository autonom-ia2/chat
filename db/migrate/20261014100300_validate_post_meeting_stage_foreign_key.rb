# Valida a FK criada sem validação na migration anterior (#1193). Só lê; não bloqueia escrita. Desfazer não tem o que
# fazer: a FK continua (quem a remove é o desfazer da migration anterior).
class ValidatePostMeetingStageForeignKey < ActiveRecord::Migration[7.2]
  def up
    validate_foreign_key :crm_agent_booking_profiles, :crm_pipeline_stages, column: :post_meeting_stage_id
  end

  def down; end
end
