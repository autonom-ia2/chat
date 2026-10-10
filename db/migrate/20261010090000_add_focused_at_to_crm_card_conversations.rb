# Assunto atual da conversa (#1141): com vários cards na mesma conversa, o card com o focused_at mais recente é o
# que a conversa trata agora. Nulo nos vínculos antigos: aí vale a ordem de sempre (principal primeiro, depois o de
# menor id), então nada muda para quem tem um card por conversa.
class AddFocusedAtToCrmCardConversations < ActiveRecord::Migration[7.2]
  def change
    add_column :crm_card_conversations, :focused_at, :datetime
  end
end
