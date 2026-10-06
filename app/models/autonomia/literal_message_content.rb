# Keeps fork-rendered text of an outgoing message literal (chat#1021).
#
# Chatwoot's Liquidable renders the content (and the WhatsApp template params) of every outgoing
# message as a Liquid template on create. Fork code that already filled the text itself hands
# Message final values that carry contact and audience data; a second Liquid pass reads that data as
# template code: a contact named "{{publico.plano}} Ana" was recorded and sent as " Ana".
#
# The marks are virtual attributes, never persisted and never assignable by request params
# (Messages::MessageBuilder builds the message from a fixed list of keys). Only fork code sets them,
# and it must do so BEFORE the message is saved, since Liquid runs in before_validation/before_create:
# - literal_content: the content was rendered by the fork (WhatsappApiCampaigns::TemplateRenderer);
# - literal_template_params: the template processed_params are final values (AI follow-up composer).
# Use Autonomia::LiteralMessageBuilder or pass the attribute to `messages.build`.
module Autonomia::LiteralMessageContent
  attr_accessor :literal_content, :literal_template_params

  private

  def liquid_processable_message?
    return false if literal_content == true

    super
  end

  def liquid_processable_template_params?
    return false if literal_template_params == true

    super
  end
end
