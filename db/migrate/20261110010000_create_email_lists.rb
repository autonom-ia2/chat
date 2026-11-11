# G52 (#2760): a lista de e-mail da conta, com nome ("Dicas do mês"). Por baixo, uma etiqueta: estar na lista é ter a
# etiqueta. A campanha de e-mail ganha o público "lista X" (email_campaigns.email_list_id) e vai para quem está na lista
# na hora do envio.
#
# Chaves:
# - account: sem cascata, como as outras tabelas de e-mail; a exclusão da conta (Autonomia::ExclusaoDaConta) apaga as
#   listas antes do DELETE da conta;
# - label: em cascata. A lista é a etiqueta: apagar a etiqueta na tela de etiquetas apaga a lista junto (a mesma regra do
#   etiquetas_nomes). Com RESTRICT, a tela de etiquetas do Chatwoot responderia erro sem dizer por quê;
# - email_campaigns.email_list_id: SET NULL, rede de segurança. Apagar a lista não apaga campanha; antes, o app tira o
#   rascunho da lista e os pendentes dela (EmailList before_destroy).
#
# O índice único [account_id, name] também atende a chave da conta (começa por ela), então account_id não ganha índice
# próprio. Só tabela e coluna novas: nada existente muda de dado.
#
# Travas: criar as chaves e a coluna pede trava curta nas tabelas que já existem. As chaves de email_lists e a de
# email_campaigns (ADD CONSTRAINT, mesmo NOT VALID) pegam SHARE ROW EXCLUSIVE em accounts, labels e email_campaigns:
# bloqueiam a escrita nelas pelo instante do comando, sem varrer linha. O ADD COLUMN pega ACCESS EXCLUSIVE em
# email_campaigns pelo mesmo instante. Todos rodam com o lock_timeout curto do strong_migrations (5 s, 3 tentativas,
# config/initializers/strong_migrations.rb): se uma transação longa segura a tabela, a migration desiste em vez de
# enfileirar as escritas atrás dela, e o deploy falha antes do tráfego. A validação da chave (VALIDATE CONSTRAINT, só
# SHARE UPDATE EXCLUSIVE, não bloqueia escrita) varre email_campaigns uma vez; a coluna acabou de nascer vazia. O
# índice da coluna nova entra concurrently (espera as transações em curso sem bloquear escrita). Cada passo pode rodar
# de novo sem erro se o deploy cair no meio.
class CreateEmailLists < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def up
    create_table :email_lists, if_not_exists: true do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.string :name, null: false
      t.references :label, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.timestamps
      t.index %i[account_id name], unique: true
    end
    add_column :email_campaigns, :email_list_id, :bigint, if_not_exists: true
    add_index :email_campaigns, :email_list_id, algorithm: :concurrently, if_not_exists: true
    add_foreign_key :email_campaigns, :email_lists, on_delete: :nullify, validate: false, if_not_exists: true
    validate_foreign_key :email_campaigns, :email_lists
  end

  def down
    remove_foreign_key :email_campaigns, :email_lists, if_exists: true
    remove_index :email_campaigns, :email_list_id, algorithm: :concurrently, if_exists: true
    remove_column :email_campaigns, :email_list_id, if_exists: true
    drop_table :email_lists, if_exists: true
  end
end
