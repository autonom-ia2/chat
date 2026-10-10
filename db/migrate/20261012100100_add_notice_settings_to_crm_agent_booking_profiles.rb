# Avisos da página de agendamento (#1192, F2-A): caixa de WhatsApp que manda os avisos (nula = sem avisos), jogo de
# avisos pronto (J5-A8), modelos aprovados por aviso e prazo para o cliente cancelar ou remarcar (J5-A3).
class AddNoticeSettingsToCrmAgentBookingProfiles < ActiveRecord::Migration[7.2]
  def change
    change_table :crm_agent_booking_profiles, bulk: true do |t|
      t.bigint :notice_inbox_id
      t.string :notice_preset, default: 'standard', null: false
      t.jsonb :notice_templates, default: {}, null: false
      t.integer :cancel_until_minutes, default: 120, null: false
    end
  end
end
