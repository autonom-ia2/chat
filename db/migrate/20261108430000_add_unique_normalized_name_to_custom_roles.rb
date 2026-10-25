# Um nome de função por conta, sem diferenciar maiúsculas nem espaços nas pontas (#2185). A validação do modelo
# avisa na tela; o índice segura duas gravações ao mesmo tempo. Produção conferida em 25/10: 0 repetidos nas duas stacks.
class AddUniqueNormalizedNameToCustomRoles < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  NOME = 'index_custom_roles_on_account_id_and_normalized_name'.freeze

  def up
    add_index :custom_roles, 'account_id, lower(trim(name))',
              unique: true, name: NOME, algorithm: :concurrently, if_not_exists: true
  end

  def down
    remove_index :custom_roles, name: NOME, algorithm: :concurrently, if_exists: true
  end
end
