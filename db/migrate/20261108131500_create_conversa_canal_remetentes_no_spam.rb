# Spam por caixa e remetente (#1809, decisão do Rodrigo, 18/10: "só a caixa de email"). Marcar Spam bloqueia aquele
# endereço só naquela caixa de e-mail; o contato (contacts.blocked) e os outros canais dele não mudam. Tabela própria do
# fork. O endereço fica em minúsculas. FK com CASCADE: apagar a caixa apaga as linhas.
class CreateConversaCanalRemetentesNoSpam < ActiveRecord::Migration[7.2]
  def change
    create_table :conversa_canal_remetentes_no_spam do |t|
      t.bigint :account_id, null: false
      t.bigint :inbox_id, null: false
      t.string :email, null: false
      t.bigint :user_id
      t.timestamps
    end
    add_index :conversa_canal_remetentes_no_spam, %i[inbox_id email], unique: true
    add_foreign_key :conversa_canal_remetentes_no_spam, :inboxes, on_delete: :cascade
  end
end
