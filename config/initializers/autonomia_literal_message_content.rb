# frozen_string_literal: true

# chat#1021: fork-rendered outgoing messages (content_attributes['literal_content']) skip
# Chatwoot's Liquid pass, so contact and audience values stay literal. See
# app/models/autonomia/literal_message_content.rb.
Rails.application.config.to_prepare do
  Message.prepend(Autonomia::LiteralMessageContent) unless Message <= Autonomia::LiteralMessageContent
end
