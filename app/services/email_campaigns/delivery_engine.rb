module EmailCampaigns
  # Batch delivery respecting the SES max send rate. Idempotent: only sends to pending
  # recipients; skips suppressed; persists per-recipient ses_message_id/status/last_error;
  # refreshes counters; marks the campaign sent when no pending remain. Defensive: a single
  # recipient failure never strands the run.
  class DeliveryEngine
    BATCH_SIZE = 100
    SEND_INTERVAL = (1.0 / EmailCampaigns::DeliveryConfig.max_send_rate).seconds

    def initialize(campaign)
      @campaign = campaign
    end

    def perform
      return unless EmailCampaigns::Config.enabled?

      EmailCampaigns::Reputation::CampaignDeliveryLock.synchronize(@campaign.id) { deliver_batch }
    end

    private

    def deliver_batch
      return unless eligible?

      @admission = EmailCampaigns::Reputation::Admission.new(@campaign)
      return if @admission.park_if_blocked!

      @campaign.mark_sending! if @campaign.scheduled?
      sender = EmailCampaigns::Ses::Sender.new(@campaign.sender_identity)

      @campaign.email_campaign_recipients.pending.find_each(batch_size: BATCH_SIZE) do |recipient|
        break unless @campaign.reload.sending?
        break if @campaign.recipient_import_active? || @admission.park_if_blocked!

        deliver_one(recipient, sender)
        sleep(SEND_INTERVAL) if SEND_INTERVAL.positive?
      end

      @campaign.finalize! if @campaign.reload.sending? && no_pending?
    end

    def eligible?
      @campaign.reload
      return false unless @campaign.sending? || @campaign.scheduled?
      return false unless @campaign.sender_identity&.usable?
      return false if @campaign.recipient_import_active?

      true
    end

    def deliver_one(recipient, sender, _suppressed = nil)
      gate = EmailCampaigns::DeliveryClaim.new(@campaign)
      return unless gate.prepare(recipient) == :ready

      rendered = render(recipient)
      tracked_html = EmailCampaigns::Tracking::Injector.new(recipient, rendered[:body_html]).perform
      headers = unsubscribe_headers(recipient)
      claimed = gate.claim(recipient) == :claimed
      return unless claimed

      message_id = dispatch(sender, recipient, rendered, tracked_html, headers)
      # SES has ACCEPTED the message by here — never route a post-send failure through the
      # transient-retry path (that would re-queue + re-send a delivered message = duplicate email).
      persist_sent!(recipient, message_id)
    rescue StandardError => e
      Rails.logger.error("[EmailCampaigns::DeliveryEngine] campaign=#{@campaign.id} recipient=#{recipient.id} #{e.message}")
      handle_send_failure(recipient, e) if claimed
    ensure
      @campaign.refresh_counters!
    end

    def dispatch(sender, recipient, rendered, tracked_html, headers)
      sender.deliver(
        to: recipient.email,
        subject: rendered[:subject],
        html_body: tracked_html,
        reply_to: @campaign.reply_to.presence || default_reply_to,
        from_email: from_email,
        headers: headers
      )
    end

    # Post-send bookkeeping. The claim already flipped the row to :sent; persist the message_id.
    # If the local write fails, give up WITHOUT re-queueing — the row
    # stays :sent (at-most-once), we only lose the ses_message_id linkage for that recipient.
    def persist_sent!(recipient, message_id)
      EmailCampaigns::Reputation::Admission.new(@campaign).with_delivery_locks(recipient) do
        recipient.update_columns(ses_message_id: message_id, sent_at: Time.current, last_error: nil, updated_at: Time.current)
      end
    rescue StandardError => e
      Rails.logger.error("[EmailCampaigns::DeliveryEngine] post-send persist failed campaign=#{@campaign.id} " \
                         "recipient=#{recipient.id} ses_message_id=#{message_id} #{e.message}")
    end

    # Only an explicit provider rejection for throttling is safe to retry. Timeouts,
    # connection loss and server failures may follow acceptance: never blind-resend.
    def handle_send_failure(recipient, error)
      EmailCampaigns::Reputation::Admission.new(@campaign).with_delivery_locks(recipient) do
        next unless recipient.sent? && recipient.sent_at.nil? && recipient.ses_message_id.blank?

        if error.is_a?(EmailCampaigns::Ses::Error) && error.message.match?(/\A429\b/)
          retry_rejected!(recipient, error)
        else
          recipient.mark_failed!(error.message)
        end
      end
    end

    def retry_rejected!(recipient, error)
      if @campaign.terminal?
        recipient.update_columns(status: EmailCampaignRecipient.statuses[:suppressed], updated_at: Time.current)
      else
        recipient.register_attempt!(error.message)
      end
    end

    def render(recipient)
      renderer = EmailCampaigns::TemplateRenderer.new(recipient)
      { subject: renderer.render(@campaign.subject),
        body_html: inject_preheader(renderer.render(@campaign.body_html), renderer.render(@campaign.preheader)) }
    end

    # Inject a hidden preheader snippet right after <body> (or at the top of the html) so inbox
    # preview text shows the campaign's preheader. Padded with zero-width/non-breaking chars so the
    # client doesn't pull body content into the preview. The text is already rendered through the
    # TemplateRenderer (placeholders supported).
    def inject_preheader(html, preheader)
      return html if preheader.blank?

      snippet = '<div style="display:none;visibility:hidden;max-height:0;overflow:hidden;mso-hide:all;' \
                "font-size:0;line-height:0;color:transparent;\">#{preheader}#{'&zwnj;&nbsp;' * 60}</div>"
      if html =~ /<body[^>]*>/i
        html.sub(/(<body[^>]*>)/i) { "#{Regexp.last_match(1)}#{snippet}" }
      else
        snippet + html
      end
    end

    def from_email
      name = @campaign.from_name.presence
      addr = @campaign.from_email.presence || @campaign.sender_identity.from_email.presence
      addr.present? && name.present? ? "#{name} <#{addr}>" : addr
    end

    def default_reply_to
      @campaign.sender_identity.from_email.presence
    end

    # RFC 8058 one-click unsubscribe — real per-recipient public endpoint (raw URL, no click
    # tracking rewrap).
    def unsubscribe_headers(recipient)
      url = EmailCampaigns::Unsubscribe::Token.url(recipient)
      {
        'List-Unsubscribe' => "<#{url}>",
        'List-Unsubscribe-Post' => 'List-Unsubscribe=One-Click'
      }
    end

    def no_pending?
      !@campaign.email_campaign_recipients.pending.exists?
    end
  end
end
