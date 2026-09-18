module EmailCampaigns
  module Tracking
    # Shared recording for tracking hits: creates an EmailEvent, advances recipient status,
    # refreshes campaign counters. Open is deduped per recipient (first open only). Clicks are
    # not deduped; a click also implies engagement (mark_clicked! wins over opened).
    class EventRecorder
      def initialize(recipient)
        @recipient = recipient
        @campaign = recipient.email_campaign
      end

      def record_open(payload = {})
        @recipient.with_lock do
          return if @recipient.email_events.opens.exists?

          @recipient.email_events.create!(event_type: :open, occurred_at: Time.current, payload: payload)
          @recipient.mark_opened!
        end
        @campaign.refresh_counters!
      end

      def record_click(url, payload = {})
        @recipient.with_lock do
          @recipient.email_events.create!(event_type: :click, url: url.to_s.truncate(255),
                                          occurred_at: Time.current, payload: payload)
          @recipient.mark_clicked!
        end
        @campaign.refresh_counters!
      end
    end
  end
end
