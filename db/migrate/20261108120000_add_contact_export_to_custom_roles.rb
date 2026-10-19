# Exportar a base de contatos saiu de `contact_manage` para a chave nova `contact_export` (#1845, épico #1784). Quem
# já exportava continua exportando: todo cargo com `contact_manage` ganha `contact_export`. Só dado; cargos criados
# depois nascem separados. O `down` tira a chave de todos os cargos, porque antes desta versão ela não existia; isso
# inclui quem a recebeu à mão depois do deploy, então um rollback pede conferir esses cargos.
class AddContactExportToCustomRoles < ActiveRecord::Migration[7.1]
  def up
    execute <<~SQL.squish
      UPDATE custom_roles
      SET permissions = array_append(permissions, 'contact_export'), updated_at = NOW()
      WHERE 'contact_manage' = ANY(permissions) AND NOT ('contact_export' = ANY(permissions))
    SQL
  end

  def down
    execute <<~SQL.squish
      UPDATE custom_roles
      SET permissions = array_remove(permissions, 'contact_export'), updated_at = NOW()
      WHERE 'contact_export' = ANY(permissions)
    SQL
  end
end
