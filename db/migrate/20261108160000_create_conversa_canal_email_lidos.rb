# "Lido" do e-mail nos dois sentidos com o servidor IMAP do cliente (#1870). Tabelas próprias do fork, sem coluna nas
# tabelas do Chatwoot. FKs com CASCADE: apagar a conta, a caixa ou a mensagem apaga as linhas.
# - conversa_canal_email_lidos: uma linha por e-mail recebido (Message) da caixa: UID no INBOX do servidor, a
#   UIDVALIDITY em que ele vale, o último \Seen sincronizado (é ele que impede o servidor de desfazer um "marcar não lida"
#   daqui) e quando o servidor tirou o \Seen depois de lido (o painel não regrava o \Seen por cima da escolha de lá).
# - conversa_canal_email_lido_caixas: o ponto de partida de cada caixa (nada anterior a ele é marcado, em nenhum sentido)
#   e a última sincronização.
class CreateConversaCanalEmailLidos < ActiveRecord::Migration[7.2]
  def change
    criar_linhas_dos_emails
    criar_caixas
  end

  private

  def criar_linhas_dos_emails
    create_table :conversa_canal_email_lidos do |t|
      t.bigint :account_id, null: false
      t.bigint :inbox_id, null: false
      t.bigint :message_id, null: false
      t.bigint :uid
      t.bigint :uidvalidity
      t.boolean :seen_no_servidor, null: false, default: false
      t.datetime :desmarcado_no_servidor_em
      t.datetime :sincronizado_em
      t.timestamps
    end
    add_index :conversa_canal_email_lidos, :message_id, unique: true
    add_index :conversa_canal_email_lidos, %i[inbox_id uid]
    add_index :conversa_canal_email_lidos, :account_id
    add_foreign_key :conversa_canal_email_lidos, :accounts, on_delete: :cascade
    add_foreign_key :conversa_canal_email_lidos, :inboxes, on_delete: :cascade
    add_foreign_key :conversa_canal_email_lidos, :messages, on_delete: :cascade
  end

  def criar_caixas
    create_table :conversa_canal_email_lido_caixas do |t|
      t.bigint :account_id, null: false
      t.bigint :inbox_id, null: false
      t.datetime :ponto_de_partida, null: false
      t.datetime :sincronizado_em
      t.timestamps
    end
    add_index :conversa_canal_email_lido_caixas, :inbox_id, unique: true
    add_index :conversa_canal_email_lido_caixas, :account_id
    add_foreign_key :conversa_canal_email_lido_caixas, :accounts, on_delete: :cascade
    add_foreign_key :conversa_canal_email_lido_caixas, :inboxes, on_delete: :cascade
  end
end
