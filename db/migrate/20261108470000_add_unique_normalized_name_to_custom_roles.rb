# Ciclo de vida da função (#2185).
# - Um nome por conta, sem diferenciar maiúsculas nem espaços nas pontas. A validação do modelo avisa na tela; o índice
#   segura duas gravações ao mesmo tempo. Produção conferida em 25/10: 0 repetidos nas duas stacks.
# - account_users.custom_role_id passa a apontar para uma função que existe. Sem isso, quem ganhava a função enquanto
#   ela era excluída ficava com um id solto e virava agente comum em silêncio. NOT VALID: vale para toda gravação nova
#   e não lê as linhas antigas.
class AddUniqueNormalizedNameToCustomRoles < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  INDICE = 'index_custom_roles_on_account_id_and_normalized_name'.freeze

  def up
    add_index :custom_roles, 'account_id, lower(trim(name))', unique: true, name: INDICE, algorithm: :concurrently
    add_foreign_key :account_users, :custom_roles, validate: false
  end

  def down
    remove_foreign_key :account_users, :custom_roles
    remove_index :custom_roles, name: INDICE, algorithm: :concurrently
  end
end
