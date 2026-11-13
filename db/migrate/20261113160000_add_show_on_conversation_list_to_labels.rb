# #2996: a etiqueta escolhe se aparece no card da lista de conversas. Nasce desligada em todas,
# inclusive nas que já existem, para nenhuma lista mudar sozinha.
class AddShowOnConversationListToLabels < ActiveRecord::Migration[7.2]
  def change
    add_column :labels, :show_on_conversation_list, :boolean, default: false, null: false
  end
end
