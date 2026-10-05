module WhatsappApiCampaigns
  class ConversationRecorder
    include FileTypeHelper

    def initialize(recipient:, rendered_body:)
      @recipient = recipient
      @campaign = recipient.whatsapp_api_campaign
      @rendered_body = rendered_body.to_s
    end

    def perform
      return existing_message if existing_message.present?

      created_message = nil
      ActiveRecord::Base.transaction do
        message = Message.find_by(account_id: @campaign.account_id, inbox_id: @campaign.inbox_id, source_id: source_id)
        if message.present?
          @recipient.update!(conversation: message.conversation, message: message)
          created_message = message
          next
        end

        conversation = find_or_create_conversation
        created_message = create_message!(conversation)
        @recipient.update!(
          conversation: conversation,
          message: created_message,
          rendered_body_sha256: OpenSSL::Digest::SHA256.hexdigest(@rendered_body)
        )
      end
      created_message
    end

    private

    def existing_message
      @existing_message ||= @recipient.message
    end

    def find_or_create_conversation
      contact_inbox = find_or_create_contact_inbox
      ConversationBuilder.new(params: conversation_params, contact_inbox: contact_inbox).perform
    end

    def find_or_create_contact_inbox
      ContactInbox.where(contact_id: @recipient.contact_id, inbox_id: @campaign.inbox_id).first ||
        ContactInboxBuilder.new(contact: @recipient.contact, inbox: @campaign.inbox, source_id: nil).perform
    end

    def conversation_params
      ActionController::Parameters.new(
        status: 'open',
        additional_attributes: {
          whatsapp_api_campaign_id: @campaign.id,
          whatsapp_api_campaign_recipient_id: @recipient.id
        }
      )
    end

    def create_message!(conversation)
      message = conversation.messages.build(
        account_id: @campaign.account_id,
        inbox_id: @campaign.inbox_id,
        message_type: :outgoing,
        content: @rendered_body.presence,
        content_type: :text,
        # Already filled by TemplateRenderer: contact and audience values stay literal (chat#1021).
        content_attributes: Autonomia::LiteralMessageContent.attributes,
        sender: @campaign.created_by,
        source_id: source_id,
        additional_attributes: {
          whatsapp_api_campaign_id: @campaign.id,
          whatsapp_api_campaign_recipient_id: @recipient.id
        }
      )
      attach_media(message)
      message.save!
      message
    end

    def attach_media(message)
      return unless @campaign.media_file.attached?

      blob = @campaign.media_file.blob
      attachment = message.attachments.build(account_id: @campaign.account_id, file: blob)
      attachment.file_type = file_type(blob.content_type)
    end

    def source_id
      @source_id ||= "whatsapp_api_campaign:#{@campaign.id}:#{@recipient.id}"
    end
  end
end
