module WhatsappApiCampaigns
  class DeliveryEngine
    def initialize(campaign)
      @campaign = campaign
    end

    def perform
      return unless Config.enabled?
      return unless eligible_campaign?

      recover_interrupted_sending_recipients!
      recipient = lock_next_recipient
      return wait_for_in_flight_or_finish! if recipient.blank?

      process_recipient(recipient)
      schedule_next_or_finish
    end

    private

    def eligible_campaign?
      @campaign.reload
      return false unless @campaign.running?
      return false unless @campaign.inbox.api? && @campaign.inbox.channel.whatsapp_api_campaign_channel?

      first_running_campaign_for_inbox?
    end

    def first_running_campaign_for_inbox?
      first_campaign = WhatsappApiCampaign.running.where(inbox_id: @campaign.inbox_id).order(:scheduled_at, :id).first
      return true if first_campaign&.id == @campaign.id

      DeliveryJob.set(wait: Config.random_delay_seconds.seconds).perform_later(@campaign.id)
      false
    end

    def lock_next_recipient
      recipient = nil
      ActiveRecord::Base.transaction do
        recipient = @campaign.whatsapp_api_campaign_recipients.pending.order(:id).lock('FOR UPDATE SKIP LOCKED').first
        next if recipient.blank?

        recipient.update!(status: :sending, attempts: recipient.attempts + 1, started_at: Time.current)
      end
      recipient
    end

    def recover_interrupted_sending_recipients!
      threshold = Config.sending_stale_after_seconds.seconds.ago
      @campaign.whatsapp_api_campaign_recipients.sending.where('updated_at < ?', threshold).lock('FOR UPDATE SKIP LOCKED').find_each do |recipient|
        existing_message = message_for(recipient)
        if existing_message.present?
          recipient.update!(status: :sent, message: existing_message, conversation: existing_message.conversation, sent_at: Time.current)
        elsif recipient.attempts < Config.max_attempts
          recipient.update!(status: :pending, last_error_message: 'recovered_interrupted_sending')
        else
          recipient.mark_failed!('sending_timeout')
        end
      end
    end

    def process_recipient(recipient)
      @campaign.reload
      recipient.reload
      return if !@campaign.running? || !recipient.sending?

      if recipient.message_id.present?
        recipient.update!(status: :sent, sent_at: Time.current)
        return
      end

      # chat#737: o público foi resolvido no início; quem recusou depois não recebe. Lê do banco a cada mensagem.
      return recipient.mark_opted_out! if Contact.opted_out.exists?(id: recipient.contact_id)

      rendered_body = TemplateRenderer.new(template: @campaign.message_body, contact: recipient.contact).render
      message = ConversationRecorder.new(recipient: recipient, rendered_body: rendered_body).perform
      mark_recipient_sent!(recipient, message)
    rescue StandardError => e
      handle_recipient_failure(recipient, e)
    ensure
      @campaign.refresh_counters!
    end

    def handle_recipient_failure(recipient, error)
      @campaign.reload
      if @campaign.cancelled?
        recipient.update!(status: :cancelled, cancelled_at: Time.current, last_error_message: error.message.to_s.truncate(500))
      elsif recipient.attempts < Config.max_attempts && @campaign.running?
        recipient.update!(status: :pending, last_error_message: error.message.to_s.truncate(500))
      else
        recipient.mark_failed!(error.message)
      end
    end

    def schedule_next_or_finish
      @campaign.reload
      return unless @campaign.running?

      if @campaign.whatsapp_api_campaign_recipients.pending.exists?
        DeliveryJob.set(wait: Config.random_delay_seconds.seconds).perform_later(@campaign.id)
      elsif @campaign.whatsapp_api_campaign_recipients.sending.exists?
        DeliveryJob.set(wait: Config.sending_stale_after_seconds.seconds).perform_later(@campaign.id)
      else
        finish_campaign!
      end
    end

    def wait_for_in_flight_or_finish!
      if @campaign.whatsapp_api_campaign_recipients.sending.exists?
        DeliveryJob.set(wait: Config.sending_stale_after_seconds.seconds).perform_later(@campaign.id)
      else
        finish_campaign!
      end
    end

    def finish_campaign!
      @campaign.with_lock do
        @campaign.reload
        return unless @campaign.running?
        return wait_for_in_flight_or_finish! if @campaign.whatsapp_api_campaign_recipients.sending.exists?

        @campaign.refresh_counters!
        new_status = @campaign.failed_count.positive? ? :completed_with_failures : :completed
        @campaign.update!(status: new_status, completed_at: Time.current)
      end
    end

    def mark_recipient_sent!(recipient, message)
      updated_rows = WhatsappApiCampaignRecipient.where(id: recipient.id, status: WhatsappApiCampaignRecipient.statuses[:sending]).update_all(
        status: WhatsappApiCampaignRecipient.statuses[:sent],
        message_id: message.id,
        conversation_id: message.conversation_id,
        sent_at: Time.current,
        last_error_message: nil,
        updated_at: Time.current
      )
      recipient.reload if updated_rows.zero?
    end

    def message_for(recipient)
      return recipient.message if recipient.message_id.present?

      Message.find_by(account_id: @campaign.account_id, inbox_id: @campaign.inbox_id, source_id: source_id_for(recipient))
    end

    def source_id_for(recipient)
      "whatsapp_api_campaign:#{@campaign.id}:#{recipient.id}"
    end
  end
end
