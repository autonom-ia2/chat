# Multifunil (#1260): quem escolheu o assunto atual da conversa. Preenchido quando uma pessoa foca o card (botão ou
# aceite de sugestão); nulo quando foi a IA ou o sistema. A IA de assunto não desfaz a escolha de uma pessoa por algumas
# horas. Lido sempre junto do vínculo, que já é buscado pela conversa (índice existente): sem índice próprio.
class AddFocusedByToCrmCardConversations < ActiveRecord::Migration[7.2]
  def change
    add_column :crm_card_conversations, :focused_by_id, :bigint
  end
end
