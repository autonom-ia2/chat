# frozen_string_literal: true

# #2216 — a mensagem da gaveta Nova conversa reabre a conversa resolvida ou adiada da caixa com "Reabrir a mesma
# conversa", sem mudar quem cuida. Prepends próprios; o controller e o modelo do Chatwoot ficam intactos. Ver
# Conversations::ReabrirAoEscreverNaMensagem e Conversations::ReabrirSemRodizio.
Rails.application.config.to_prepare do
  Conversation.prepend(Conversations::ReabrirSemRodizio) unless Conversation <= Conversations::ReabrirSemRodizio
  mensagens = Api::V1::Accounts::Conversations::MessagesController
  mensagens.prepend(Conversations::ReabrirAoEscreverNaMensagem) unless mensagens <= Conversations::ReabrirAoEscreverNaMensagem
end
