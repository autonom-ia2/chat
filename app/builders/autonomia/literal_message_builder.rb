# Messages::MessageBuilder for text the fork already rendered (chat#1021).
#
# Sets the virtual marks of Autonomia::LiteralMessageContent on the message before it is saved, so
# Chatwoot's Liquid pass leaves the fork-filled values literal. The marks come from these keyword
# arguments, never from params: a client sending content_attributes['literal_content'] gets nothing.
class Autonomia::LiteralMessageBuilder < Messages::MessageBuilder
  def initialize(user, conversation, params, literal_content: false, literal_template_params: false)
    super(user, conversation, params)
    @literal_content = literal_content
    @literal_template_params = literal_template_params
  end

  private

  def message_params
    super.merge(literal_content: @literal_content, literal_template_params: @literal_template_params)
  end
end
