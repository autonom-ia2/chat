# ÍNDICES DA PESQUISA NO LEAD (chat#679, E3 frente C), criados sem travar a escrita na tabela de leads.
#
# O varredor procura por estado; o reaproveitamento procura o mesmo lugar já pesquisado em qualquer conta.
class AddResearchIndexesToAutonomiaProspectingLeads < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    add_index :autonomia_prospecting_leads, :company_profile_id,
              algorithm: :concurrently, name: 'idx_autonomia_prospecting_leads_company_profile'
    add_index :autonomia_prospecting_leads, :company_research_status,
              algorithm: :concurrently, name: 'idx_autonomia_prospecting_leads_research_status',
              where: "company_research_status IN ('queued', 'researching', 'waiting_capacity')"
    add_index :autonomia_prospecting_leads, [:provider, :provider_place_id],
              algorithm: :concurrently, name: 'idx_autonomia_prospecting_leads_researched_place',
              where: 'company_profile_id IS NOT NULL'
  end
end
