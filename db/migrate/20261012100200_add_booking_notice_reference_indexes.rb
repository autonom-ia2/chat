# Índices das colunas de FK novas (#1192) antes de qualquer `on_delete`: sem eles, apagar uma conversa ou caixa
# varreria a tabela inteira. Concorrente, para não travar escrita em reuniões e páginas.
class AddBookingNoticeReferenceIndexes < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    add_index :crm_meetings, :conversation_id, algorithm: :concurrently, if_not_exists: true
    add_index :crm_agent_booking_profiles, :notice_inbox_id, algorithm: :concurrently, if_not_exists: true
  end
end
