# frozen_string_literal: true

# #1883 (Números F2): `da_ia` e `esperando_min` na lista de conversas, por cima do ConversationFinder do Chatwoot
# (app/finders/crm/conversation_finder_com_filtros_do_link.rb). Depende do módulo das pastas do e-mail, que entra em
# config/initializers/conversa_canal_email.rb: no Spam e na Lixeira, a pasta manda.
Rails.application.config.to_prepare do
  ConversationFinder.prepend(Crm::ConversationFinderComFiltrosDoLink) unless ConversationFinder <= Crm::ConversationFinderComFiltrosDoLink
end
