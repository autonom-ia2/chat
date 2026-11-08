# frozen_string_literal: true

# #1941 — a conversa "Integração WhatsApp" do conector fora da lista, das contagens, dos filtros e das não lidas. Ver
# Waha::IntegracaoDoConector.
Rails.application.config.to_prepare do
  Conversation.include(Waha::IntegracaoDoConector) unless Conversation <= Waha::IntegracaoDoConector
  ConversationFinder.prepend(Waha::ConversationFinderSemIntegracao) unless ConversationFinder <= Waha::ConversationFinderSemIntegracao
  Conversations::FilterService.prepend(Waha::FilterServiceSemIntegracao) unless Conversations::FilterService <= Waha::FilterServiceSemIntegracao
  [Conversations::UnreadCounts::Builder, Conversations::UnreadCounts::FilteredCounter,
   Conversations::UnreadCounts::FilterQueryCounter].each do |counter|
    counter.prepend(Waha::NaoLidasSemIntegracao) unless counter <= Waha::NaoLidasSemIntegracao
  end
  refresher = Conversations::UnreadCounts::Refresher
  refresher.prepend(Waha::NaoLidasSemIntegracao::Refresher) unless refresher <= Waha::NaoLidasSemIntegracao::Refresher
end
