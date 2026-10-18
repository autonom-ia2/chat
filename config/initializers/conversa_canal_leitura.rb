# frozen_string_literal: true

# #1702 — lida no WhatsApp do cliente quando o atendente abre a conversa. Prepend próprio; o controller do Chatwoot fica
# intacto. Ver ConversaCanal::LeituraAoAbrir.
Rails.application.config.to_prepare do
  unless Api::V1::Accounts::ConversationsController <= ConversaCanal::LeituraAoAbrir
    Api::V1::Accounts::ConversationsController.prepend(ConversaCanal::LeituraAoAbrir)
  end
end
