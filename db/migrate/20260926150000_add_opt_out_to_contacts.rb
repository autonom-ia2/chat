# RECUSA DE MENSAGENS ATIVAS NO CONTATO (chat#713, chat#737).
#
# A recusa passa a morar no próprio contato, para campanhas e follow-ups automáticos respeitarem por qualquer caminho.
# opted_out_at nulo quer dizer "não recusou": nada muda para os contatos existentes.
# - opt_out_source: 'prospecting', 'email_unsubscribe' ou 'manual' (validado no modelo, ver ContactOptOut).
# - opted_out_by_id: usuário que marcou à mão. Apagar o usuário só esquece o autor, a recusa fica.
#
# Tabela contacts é grande em produção, por isso:
# - colunas sem default (só metadado no Postgres, sem reescrever a tabela);
# - chave estrangeira criada sem validar: a coluna nasce vazia, não há linha a conferir, e a trava fica curta.
#   Ela vale para toda escrita nova e para o on_delete;
# - índice parcial criado em modo concorrente, sem travar escrita. Serve para listar os recusados da conta.
class AddOptOutToContacts < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    add_column :contacts, :opted_out_at, :datetime, if_not_exists: true
    add_column :contacts, :opt_out_source, :string, if_not_exists: true
    add_column :contacts, :opted_out_by_id, :bigint, if_not_exists: true
    add_foreign_key :contacts, :users, column: :opted_out_by_id, on_delete: :nullify, validate: false, if_not_exists: true
    add_index :contacts, :account_id, name: 'index_contacts_on_account_id_opted_out',
                                      where: 'opted_out_at IS NOT NULL', algorithm: :concurrently
  end
end
