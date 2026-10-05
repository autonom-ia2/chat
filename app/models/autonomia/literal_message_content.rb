# Keeps the content of a fork-rendered outgoing message literal (chat#1021).
#
# Chatwoot's Liquidable renders every outgoing message content as a Liquid template on create.
# Fork code that already filled a template itself (WhatsappApiCampaigns::TemplateRenderer, used
# by the WhatsApp API campaign delivery and the CRM follow-up on Channel::Api) hands Message a
# finished text that carries contact and audience data. A second Liquid pass reads that data as
# template code: a contact named "{{publico.plano}} Ana" was recorded and sent as " Ana".
#
# Messages created with `attributes` in content_attributes skip the Liquid pass on their content.
# Anything else (agent replies, canned responses, automations, API clients) is unchanged.
module Autonomia::LiteralMessageContent
  FLAG = 'literal_content'.freeze

  # content_attributes that mark a message whose content the fork already rendered.
  def self.attributes
    { FLAG => true }
  end

  private

  def liquid_processable_message?
    return false if content_attributes.to_h.with_indifferent_access[FLAG] == true

    super
  end
end
