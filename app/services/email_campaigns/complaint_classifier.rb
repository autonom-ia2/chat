# Shared by ingestion, reputation and downstream reports/backfills. Input is the
# complaint object, not the notification envelope. Unknown/missing subtypes are real.
class EmailCampaigns::ComplaintClassifier
  PREVENTED_SUBTYPES = %w[OnAccountSuppressionList OnTenantSuppressionList].freeze
  PREVENTED_SUBTYPE_SQL = "COALESCE(payload #>> '{complaint,complaintSubType}', '') IN " \
                          "('#{PREVENTED_SUBTYPES.join("', '")}')".freeze
  PROVIDER_PREVENTED_SQL = "event_type = 4 AND (#{PREVENTED_SUBTYPE_SQL})".freeze
  REAL_COMPLAINT_SQL = "event_type = 4 AND NOT (#{PREVENTED_SUBTYPE_SQL})".freeze

  def self.provider_prevented?(complaint)
    PREVENTED_SUBTYPES.include?((complaint || {})['complaintSubType'])
  end

  def self.real_complaint?(complaint)
    !provider_prevented?(complaint)
  end
end
