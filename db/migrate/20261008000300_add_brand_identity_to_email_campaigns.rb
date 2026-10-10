# Identidade visual usada por um e-mail com IA (#1076) e os avisos do controle de qualidade da última
# geração. email_campaigns é tabela do fork (módulos Autonomia), então a coluna fica nela.
#   brand_identity:      { kit_id, name, mode: light|dark, source: kit|site, source_url }
#   ai_quality_warnings: [{ check, detail }]
class AddBrandIdentityToEmailCampaigns < ActiveRecord::Migration[7.1]
  def change
    add_column :email_campaigns, :brand_identity, :jsonb, default: {}, null: false
    add_column :email_campaigns, :ai_quality_warnings, :jsonb, default: [], null: false
  end
end
