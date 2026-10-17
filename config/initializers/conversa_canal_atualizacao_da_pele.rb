# frozen_string_literal: true

# #1702 — atualização só de marca da pele (reação, lida, prévia, áudio ouvido, apagada pelo cliente) não chega ao robô
# nem ao webhook da caixa API. Ver ConversaCanal::AtualizacaoDaPele.
Rails.application.config.to_prepare do
  AgentBotListener.prepend(ConversaCanal::RoboSemAtualizacaoDaPele) unless AgentBotListener <= ConversaCanal::RoboSemAtualizacaoDaPele
  WebhookListener.prepend(ConversaCanal::WebhookSemAtualizacaoDaPele) unless WebhookListener <= ConversaCanal::WebhookSemAtualizacaoDaPele
end
