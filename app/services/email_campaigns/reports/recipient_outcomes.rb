# At most two evidence rows per recipient in the current page/CSV batch.
class EmailCampaigns::Reports::RecipientOutcomes
  def initialize(recipients)
    @recipients = recipients.reorder(nil)
  end

  def call
    latest = EmailEvent.where(event_type: %i[bounce complaint], recipient_id: @recipients.select(:id))
                       .select(Arel.sql("DISTINCT ON (recipient_id, event_type) recipient_id, event_type, payload -> 'bounce' AS bounce, " \
                                        "payload -> 'complaint' AS complaint"))
                       .order(:recipient_id, :event_type, occurred_at: :desc, id: :desc)
    EmailEvent.unscoped.from("(#{latest.to_sql}) email_events")
              .pluck(:recipient_id, :event_type, Arel.sql('bounce'), Arel.sql('complaint'))
              .each_with_object({}) do |(id, type, bounce, complaint), result|
      result[id] ||= {}
      if type == 'bounce'
        result[id][:bounce] = EmailCampaigns::BounceClassifier.call(bounce.is_a?(Hash) ? bounce : {})
      else
        result[id][:complaint_prevented] = EmailCampaigns::ComplaintClassifier.provider_prevented?(complaint)
      end
    end
  end
end
