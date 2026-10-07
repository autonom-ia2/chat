# Importar modelo de e-mail (#1099, entrega C): o que as telas mostram além do resultado — a prévia do original já limpo
# (com as imagens copiadas ou em cinza, sem links), o passo em que o job está (para as frases de "Preparando") e as
# correções que a pessoa já fez (para cada aviso resolvido ficar verde). Tabela própria do fork.
class AddScreenFieldsToEmailCampaignTemplateImports < ActiveRecord::Migration[7.2]
  def change
    change_table :email_campaign_template_imports, bulk: true do |t|
      t.text :preview_html
      t.jsonb :progress, null: false, default: {}
      t.jsonb :fixes, null: false, default: []
    end
  end
end
