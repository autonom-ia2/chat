# Arquivar card saiu de `crm_manage_cards` para a chave nova `crm_delete_cards` (#1874, épico #1784). Quem já arquivava
# continua arquivando: todo cargo com `crm_manage_cards` ganha `crm_delete_cards`, inclusive o cargo gerenciado de cada
# token de integração do CRM. Só dado; cargos criados depois nascem separados. O `down` tira a chave de todos os cargos,
# porque antes desta versão ela não existia; isso inclui quem a recebeu à mão depois do deploy, então um rollback pede
# conferir esses cargos.
class AddCrmDeleteCardsToCustomRoles < ActiveRecord::Migration[7.1]
  def up
    execute <<~SQL.squish
      UPDATE custom_roles
      SET permissions = array_append(permissions, 'crm_delete_cards'), updated_at = NOW()
      WHERE 'crm_manage_cards' = ANY(permissions) AND NOT ('crm_delete_cards' = ANY(permissions))
    SQL
  end

  def down
    execute <<~SQL.squish
      UPDATE custom_roles
      SET permissions = array_remove(permissions, 'crm_delete_cards'), updated_at = NOW()
      WHERE 'crm_delete_cards' = ANY(permissions)
    SQL
  end
end
