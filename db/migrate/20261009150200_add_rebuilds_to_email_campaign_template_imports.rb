# Importar modelo de e-mail (#1099, entrega D): o estado de cada "Refazer para editar" — o trecho que a IA está
# refazendo, o que ficou pronto e o que não deu — guardado por trecho na própria importação. Tabela própria do fork.
class AddRebuildsToEmailCampaignTemplateImports < ActiveRecord::Migration[7.2]
  def change
    add_column :email_campaign_template_imports, :rebuilds, :jsonb, null: false, default: {}
  end
end
