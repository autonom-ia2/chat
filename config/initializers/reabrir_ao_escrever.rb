# frozen_string_literal: true

# #2216 — começar conversa reabre a conversa resolvida ou adiada da caixa com "Reabrir a mesma conversa", sem mudar quem
# cuida: pela criação (conversa oculta) e pela mensagem com o sinal da gaveta (conversa visível). Prepends próprios; os
# controllers e o modelo do Chatwoot ficam intactos. Ver Conversations::ReabrirAoEscrever,
# Conversations::ReabrirAoEscreverNaMensagem e Conversations::ReabrirSemRodizio.
Rails.application.config.to_prepare do
  Conversation.prepend(Conversations::ReabrirSemRodizio) unless Conversation <= Conversations::ReabrirSemRodizio
  unless Api::V1::Accounts::ConversationsController <= Conversations::ReabrirAoEscrever
    Api::V1::Accounts::ConversationsController.prepend(Conversations::ReabrirAoEscrever)
  end
  mensagens = Api::V1::Accounts::Conversations::MessagesController
  mensagens.prepend(Conversations::ReabrirAoEscreverNaMensagem) unless mensagens <= Conversations::ReabrirAoEscreverNaMensagem
end
