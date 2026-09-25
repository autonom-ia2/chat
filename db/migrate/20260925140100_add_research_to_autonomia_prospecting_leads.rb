# ESTADO DA PESQUISA DE EMPRESA E DECISOR NO LEAD (chat#679, E3 frente C).
#
# Um estado por capacidade (empresa e decisor), como no Orth, com o default "not_researched" para todo lead que já
# existe. `research_started_at` marca o início da pesquisa, para o varredor achar worker que morreu sem confundir com
# pedido esperando na fila (`research_requested_at`). Só acrescenta colunas; o perfil apagado solta o lead (nullify).
class AddResearchToAutonomiaProspectingLeads < ActiveRecord::Migration[7.2]
  def change
    change_table :autonomia_prospecting_leads, bulk: true do |t|
      t.string :company_research_status, null: false, default: 'not_researched'
      t.string :decision_research_status, null: false, default: 'not_researched'
      t.datetime :research_requested_at
      t.datetime :research_started_at
      t.datetime :research_completed_at
      t.boolean :research_reused, null: false, default: false
      t.string :research_error
      t.bigint :company_profile_id
      t.integer :research_attempts, null: false, default: 0
    end

    add_foreign_key :autonomia_prospecting_leads, :autonomia_prospecting_company_profiles, column: :company_profile_id, on_delete: :nullify
  end
end
