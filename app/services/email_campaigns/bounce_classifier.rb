class EmailCampaigns::BounceClassifier
  SUBTYPE_OUTCOMES = {
    # Global suppression counts as a permanent SES bounce, without proving an invalid mailbox.
    'Suppressed' => %w[permanent provider_suppression],
    'OnAccountSuppressionList' => %w[unknown provider_suppression],
    'OnTenantSuppressionList' => %w[unknown provider_suppression],
    'EmailValidationSuppressed' => %w[unknown provider_suppression],
    'UnsubscribedRecipient' => %w[unknown unsubscribe]
  }.freeze

  def self.call(bounce)
    subtype = bounce['bounceSubType']
    classification, reason = if SUBTYPE_OUTCOMES.key?(subtype)
                               SUBTYPE_OUTCOMES.fetch(subtype)
                             elsif bounce['bounceType'] == 'Permanent'
                               # NoEmail means the address could not be extracted, not that the mailbox does not exist.
                               %w[permanent permanent_failure]
                             elsif bounce['bounceType'] == 'Transient'
                               ['temporary', subtype == 'MailboxFull' ? 'mailbox_full' : 'temporary_failure']
                             else
                               %w[unknown undetermined_bounce]
                             end
    { 'classification' => classification, 'reason_code' => reason }
  end
end
