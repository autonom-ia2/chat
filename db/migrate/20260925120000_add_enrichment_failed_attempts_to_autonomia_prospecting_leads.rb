# TENTATIVAS DE ENRIQUECIMENTO QUE FALHARAM, POR LEAD (chat#678, E2 frente D; fecha a parte de #476 sobre falha).
#
# Site fora do ar, bloqueado ou vazio passa a marcar o enriquecimento como falho, e este contador soma cada falha
# seguida (zera quando uma tentativa dá certo). É o que deixa o disparo automático parar de insistir num site que
# não responde. Coluna nova com padrão constante: o Postgres não reescreve a tabela.
class AddEnrichmentFailedAttemptsToAutonomiaProspectingLeads < ActiveRecord::Migration[7.2]
  def change
    add_column :autonomia_prospecting_leads, :enrichment_failed_attempts, :integer, default: 0, null: false
  end
end
