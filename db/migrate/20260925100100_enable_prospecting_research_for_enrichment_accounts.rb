# QUEM JÁ ENRIQUECIA LEAD CONTINUA ENRIQUECENDO (chat#683, E0).
#
# O interruptor do enriquecimento saiu da tela da conta e foi para o superadmin, como `research_enabled` em
# `accounts.internal_attributes`. A conta que tinha `enrichment_enabled` ligado ganha a pesquisa liberada, para
# ninguém perder o que tem hoje. A coluna `enrichment_enabled` fica no banco e só deixa de ser lida.
#
# O DOWN NÃO DESLIGA. Depois do deploy o superadmin pode ter ligado a pesquisa na mão, e a migration não separa
# as duas origens; desligar é decisão por conta, no console.
class EnableProspectingResearchForEnrichmentAccounts < ActiveRecord::Migration[7.2]
  def up
    execute(<<~SQL.squish)
      UPDATE accounts
      SET internal_attributes = COALESCE(internal_attributes, '{}'::jsonb)
                                || '{"autonomia_prospecting_research_enabled": true}'::jsonb
      WHERE id IN (SELECT account_id FROM autonomia_prospecting_settings WHERE enrichment_enabled = TRUE)
    SQL
  end

  def down; end
end
