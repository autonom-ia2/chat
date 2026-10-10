# FK da etapa de depois da reunião (#1193) sem validar as linhas existentes (todas nulas): não segura trava longa.
# Etapa apagada só desliga a opção; a página continua.
class AddPostMeetingStageForeignKey < ActiveRecord::Migration[7.2]
  def change
    add_foreign_key :crm_agent_booking_profiles, :crm_pipeline_stages,
                    column: :post_meeting_stage_id, on_delete: :nullify, validate: false
  end
end
