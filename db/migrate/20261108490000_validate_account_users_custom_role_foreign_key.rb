# #2219: a chave estrangeira account_users.custom_role_id -> custom_roles entrou NOT VALID no #2208 (#2185). Desde então
# toda gravação nova é conferida; aqui o banco confere também as linhas de antes e marca a chave como válida. Produção
# conferida em 25/10, só leitura: nenhuma pessoa aponta para função que não existe, nas duas stacks.
# VALIDATE CONSTRAINT pega só SHARE UPDATE EXCLUSIVE (leitura e escrita seguem); fora da transação, como os índices.
class ValidateAccountUsersCustomRoleForeignKey < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def up
    validate_foreign_key :account_users, :custom_roles
  end

  # Volta ao estado do #2208: a mesma chave, NOT VALID, que continua conferindo as gravações novas.
  def down
    remove_foreign_key :account_users, :custom_roles
    add_foreign_key :account_users, :custom_roles, validate: false
  end
end
