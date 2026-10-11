module Crm
  class WhatsappGroupDetector
    NON_DIRECT_JID_SUFFIXES = %w[@g.us @broadcast @newsletter].freeze
    WHATSAPP_CHANNEL_TYPES = %w[Channel::Whatsapp Channel::Api].freeze
    # WAHA's Chatwoot app creates the contact through the public inbox API without
    # a source_id, so the contact_inbox gets a random uuid and the WhatsApp chat id
    # lives on the contact (#1276). `waha_whatsapp_lid` is left out: @lid is 1:1 only.
    WAHA_CHAT_ID_ATTRIBUTES = %w[waha_whatsapp_chat_id waha_whatsapp_jid].freeze

    # Non-1:1 WhatsApp JIDs (WAHA/Evolution): groups end with @g.us, broadcasts
    # with @broadcast (incl. status@broadcast), channels with @newsletter.
    # Scoped to WhatsApp-capable channels so email/web ids never match.
    def self.group_conversation?(conversation)
      return false unless WHATSAPP_CHANNEL_TYPES.include?(conversation&.inbox&.channel_type)

      chat_ids(conversation).any? { |chat_id| chat_id.to_s.strip.downcase.end_with?(*NON_DIRECT_JID_SUFFIXES) }
    end

    # The source_id stays as a fallback for providers that do store the JID there.
    def self.chat_ids(conversation)
      conversation.contact&.custom_attributes.to_h.values_at(*WAHA_CHAT_ID_ATTRIBUTES) + [conversation.contact_inbox&.source_id]
    end
    private_class_method :chat_ids
  end
end
