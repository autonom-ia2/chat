# Depois da reunião (#1193, J4-A7): etapa para onde o card vai quando o agente marca "Aconteceu" e se o sistema
# pergunta antes (`ask`) ou move sozinho (`auto`). Sem etapa, nada é oferecido.
class AddPostMeetingToCrmAgentBookingProfiles < ActiveRecord::Migration[7.2]
  def change
    change_table :crm_agent_booking_profiles, bulk: true do |t|
      t.string :post_meeting_mode, default: 'ask', null: false
      t.bigint :post_meeting_stage_id
    end
  end
end
