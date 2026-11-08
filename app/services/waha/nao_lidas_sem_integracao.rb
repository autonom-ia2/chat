# Prepend nos contadores de não lidas (#1941, item 5): a conversa "Integração WhatsApp" do conector não soma no número
# de não lidas por caixa, no total do menu nem nas visões salvas (Waha::IntegracaoDoConector). Os três contadores
# (Builder, FilteredCounter e FilterQueryCounter) montam a própria base em `unread_conversations`; a atualização em
# tempo real (Refresher, a cada mensagem) decide por `unread?` (Waha::NaoLidasSemIntegracao::Refresher).
module Waha::NaoLidasSemIntegracao
  private

  def unread_conversations
    super.fora_da_integracao_whatsapp
  end
end
