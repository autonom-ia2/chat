module EmailCampaigns
  module Sns
    class EventProcessor
      def initialize(ses_event)
        @event = ses_event || {}
      end

      def process
        recipient = find_recipient
        type = { 'Delivery' => :delivered, 'Bounce' => :bounce, 'Complaint' => :complaint }[event_type]
        return unless recipient && type

        # Share the Account -> recipient order with PR439 workers during blue/green.
        processed = recipient.email_campaign.account.with_lock do
          recipient.lock!
          # One outcome of each type per dispatch. Lock closes parallel SNS replay,
          # before both metrics and quarantine occurrences. Keep the original payload.
          next false if recipient.email_events.where(event_type: type).exists?

          recipient.email_events.create!(event_type: type, occurred_at: Time.current, payload: @event)
          apply_event(recipient, type)
          true
        end
        recipient.email_campaign.refresh_counters! if processed
      end

      private

      def apply_event(recipient, type)
        case type
        when :delivered then recipient.mark_delivered!
        when :bounce then on_bounce(recipient)
        when :complaint then on_complaint(recipient)
        end
      end

      def event_type
        @event['eventType'] || @event['notificationType']
      end

      def message_id
        @event.dig('mail', 'messageId')
      end

      def find_recipient
        EmailCampaignRecipient.find_by(ses_message_id: message_id) if message_id.present?
      end

      def on_bounce(recipient)
        evidence = EmailCampaigns::BounceClassifier.call(@event.fetch('bounce', {}))
        reason = case evidence.fetch('classification')
                 when 'permanent' then 'hard_bounce'
                 when 'temporary' then 'temporary_failure'
                 else 'unknown_bounce'
                 end
        reason = evidence['reason_code'] if %w[provider_suppression unsubscribe].include?(evidence['reason_code'])
        registry(recipient).record!(reason: reason, source: 'ses', event_key: "ses:#{message_id}:bounce",
                                    occurred_at: event_time('bounce'), metadata: evidence)
        return on_unsubscribe(recipient) if reason == 'unsubscribe'

        recipient.mark_bounced! unless recipient.unsubscribed? || recipient.complained?
      end

      def on_unsubscribe(recipient)
        return if recipient.unsubscribed?

        recipient.email_events.create!(event_type: :unsubscribe, occurred_at: event_time('bounce'))
        # Like signed opt-out, SES opt-out must survive unrelated invalid legacy fields.
        recipient.update_columns(status: EmailCampaignRecipient.statuses[:unsubscribed], # rubocop:disable Rails/SkipsModelValidations
                                 last_event_at: Time.current, updated_at: Time.current)
      end

      def on_complaint(recipient)
        registry(recipient).block!(reason: 'complaint', source: 'ses', event_key: "ses:#{message_id}:complaint",
                                   occurred_at: event_time('complaint'))
        recipient.mark_complained! unless recipient.unsubscribed?
      end

      def registry(recipient)
        campaign = recipient.email_campaign
        EmailCampaigns::SuppressionRegistry.new(account: campaign.account, email: recipient.email, campaign: campaign)
      end

      def event_time(type)
        timestamp = @event.dig(type, 'timestamp') || @event.dig('mail', 'timestamp')
        timestamp.present? ? [Time.iso8601(timestamp), Time.current].min : Time.current
      rescue ArgumentError
        Time.current
      end
    end
  end
end
