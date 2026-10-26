# frozen_string_literal: true

# #2216 — começar conversa reabre a conversa resolvida ou adiada da caixa com "Reabrir a mesma conversa", sem mudar quem
# cuida. Prepends próprios; o controller e o modelo do Chatwoot ficam intactos. Ver Conversations::ReabrirAoEscrever e
# Conversations::ReabrirSemRodizio.
Rails.application.config.to_prepare do
  Conversation.prepend(Conversations::ReabrirSemRodizio) unless Conversation <= Conversations::ReabrirSemRodizio
  unless Api::V1::Accounts::ConversationsController <= Conversations::ReabrirAoEscrever
    Api::V1::Accounts::ConversationsController.prepend(Conversations::ReabrirAoEscrever)
  end
end
