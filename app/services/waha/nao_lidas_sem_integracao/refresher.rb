# Prepend em Conversations::UnreadCounts::Refresher (#1941, item 5): a atualização em tempo real das não lidas não
# conta a conversa "Integração WhatsApp" do conector (Waha::IntegracaoDoConector).
module Waha::NaoLidasSemIntegracao::Refresher
  private

  def unread?
    return false if Waha::IntegracaoDoConector.da_integracao?(conversation)

    super
  end
end
