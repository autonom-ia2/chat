module Autonomia
  module Channels
    class BroadcastGuard
      BROADCAST_SUFFIX = '@broadcast'.freeze

      def self.blocked_conversation?(conversation)
        new(conversation: conversation).blocked?
      end

      def self.blocked_destination?(destination)
        normalized_destination(destination).end_with?(BROADCAST_SUFFIX)
      end

      def self.normalized_destination(destination)
        destination.to_s.strip.downcase
      end

      def initialize(conversation:)
        @conversation = conversation
      end

      # Olha o `waha_whatsapp_chat_id` do contato e o `source_id` do ContactInbox; o jid fica de fora de propósito (#1324:
      # passar a olhá-lo muda comportamento e vai em PR próprio).
      def blocked?
        destinations.any? { |destination| self.class.blocked_destination?(destination) }
      end

      private

      def destinations
        Waha::ContactChatId.values(contact, :chat_id, :source_id, contact_inbox: contact_inbox)
      end

      def contact
        @conversation&.contact
      end

      def contact_inbox
        @conversation&.contact_inbox
      end
    end
  end
end
