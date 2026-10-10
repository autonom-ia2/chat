# Página de agendamento nova (#1188): locais, antecedência mínima, durações, marca e modelo.
# `page_version` separa as páginas antigas (1, gaveta do Kanban) das novas (2, Configurações › Agendamento),
# para a tela antiga não enxergar páginas sem caixa de e-mail.
class AddBookingV2ColumnsToCrmAgentBookingProfiles < ActiveRecord::Migration[7.2]
  def change
    change_table :crm_agent_booking_profiles, bulk: true do |t|
      t.integer :page_version, default: 1, null: false
      t.jsonb :locations, default: [], null: false
      t.integer :min_notice_minutes, default: 0, null: false
      t.jsonb :slot_durations, default: [], null: false
      t.string :contact_phone
      t.string :template_key
      t.jsonb :brand, default: {}, null: false
    end
  end
end
