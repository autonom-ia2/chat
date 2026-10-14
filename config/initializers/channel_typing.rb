# frozen_string_literal: true

# chat#1442 — "Digitando" do robô por uma chamada só ao painel (toggle_typing_status + deliver_to_channel).
# Tudo no fork por prepend; o controller do Chatwoot fica intacto.
Rails.application.config.to_prepare do
  unless Api::V1::Accounts::ConversationsController <= Conversations::ChannelTyping::ToggleEndpoint
    Api::V1::Accounts::ConversationsController.prepend(Conversations::ChannelTyping::ToggleEndpoint)
  end
end
