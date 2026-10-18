# Pastas da caixa de e-mail no painel (#1809, fase 1): Spam e Lixeira, como no Gmail, sem apagar nada e sem mexer na
# conta de e-mail do cliente. Uma linha por conversa que saiu da Entrada; restaurar apaga a linha. Tabela própria do
# fork (nenhuma coluna em tabela do Chatwoot). FK com CASCADE: apagar a conversa apaga a linha.
class CreateConversaCanalPastasDoEmail < ActiveRecord::Migration[7.2]
  def change
    create_table :conversa_canal_pastas_do_email do |t|
      t.bigint :account_id, null: false
      t.bigint :conversation_id, null: false
      t.string :pasta, null: false
      t.bigint :user_id
      t.timestamps
    end
    add_index :conversa_canal_pastas_do_email, :conversation_id, unique: true
    add_index :conversa_canal_pastas_do_email, %i[account_id pasta]
    add_foreign_key :conversa_canal_pastas_do_email, :conversations, on_delete: :cascade
    add_check_constraint :conversa_canal_pastas_do_email, "pasta IN ('spam', 'lixeira')", name: 'conversa_canal_pastas_do_email_pasta'
  end
end
