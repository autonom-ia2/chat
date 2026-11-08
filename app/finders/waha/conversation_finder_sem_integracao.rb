# Prepend em ConversationFinder (#1941, item 5): a conversa "Integração WhatsApp" do conector sai da lista e das
# contagens (Waha::IntegracaoDoConector).
module Waha::ConversationFinderSemIntegracao
  private

  def find_all_conversations
    super
    @conversations = @conversations.fora_da_integracao_whatsapp
  end
end
