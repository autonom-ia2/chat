# frozen_string_literal: true

# chat#1021: text the fork already rendered (virtual marks literal_content / literal_template_params,
# set only by fork code before save) skips Chatwoot's Liquid pass, so contact and audience values stay
# literal. See app/models/autonomia/literal_message_content.rb.
Rails.application.config.to_prepare do
  Message.prepend(Autonomia::LiteralMessageContent) unless Message <= Autonomia::LiteralMessageContent
end
