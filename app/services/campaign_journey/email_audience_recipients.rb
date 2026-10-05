# E-mail recipients of a journey campaign come from its audience (#999, PRD §8.6 and N2): one
# email_campaign_recipients row per eligible audience contact, with contact_id. Written when the
# draft is created and synced again when it is scheduled or sent, up to the first send
# (CampaignJourney::EmailAudienceGate). Everything after that is the email engine of today (§6.9): suppression and
# opt-out at send time, hygiene preflight, reputation, readiness, direct inbox limits.
#
# Who is eligible is CampaignJourney::AudienceContacts (the row brought the contact's current
# e-mail; the audience e-mail channel is on — fails closed). Suppressed addresses (unsubscribe,
# bounce, complaint) are written as `suppressed`, like the spreadsheet import; contacts that
# refused active messages (#737) stay out of the list.
class CampaignJourney::EmailAudienceRecipients
  BATCH_SIZE = 500
  # Placeholders the renderer already provides (EmailCampaigns::TemplateValidator::DEFAULT_KEYS).
  RESERVED_KEYS = %w[nome email contact unsubscribe_url].freeze

  Candidate = Struct.new(:contact, :email, :row, keyword_init: true)

  def self.candidates(campaign_import)
    return [] unless CampaignJourney::AudienceContacts.email_enabled?(campaign_import)

    matches = CampaignJourney::AudienceContacts.email_matches(campaign_import, account: campaign_import.account)
    contacts = campaign_import.account.contacts.not_opted_out.where(id: matches.map(&:contact_id)).index_by(&:id)
    matches.filter_map do |match|
      contact = contacts[match.contact_id]
      contact && Candidate.new(contact: contact, email: match.email, row: match.row)
    end
  end

  def initialize(campaign)
    @campaign = campaign
    @link = CampaignAudienceLink.for_campaign(campaign)
  end

  # Before the first send (draft or scheduled, nobody sent yet): adds who became eligible and
  # removes pending recipients that are no longer eligible. Never touches a recipient that was
  # sent or has events. Idempotent. New recipients get the hygiene preflight after commit.
  # => { added: 2, removed: 1 }
  def sync!
    return { added: 0, removed: 0 } unless syncable?

    candidates = self.class.candidates(@link.campaign_import)
    removed = remove_stale(candidates.to_set(&:email))
    added = add_missing(candidates)
    @campaign.refresh_counters! if (added + removed).positive?
    ActiveRecord.after_all_transactions_commit { EmailCampaigns::RecipientPreflightJob.enqueue(@campaign.id) } if added.positive?
    { added: added, removed: removed }
  end

  # What sync! would do now, without writing (the readiness list shows it). => { to_add:, to_remove: }
  def preview
    return { to_add: 0, to_remove: 0 } unless syncable?

    candidates = self.class.candidates(@link.campaign_import)
    eligible = candidates.to_set(&:email)
    existing = existing_emails
    { to_add: candidates.count { |candidate| existing.exclude?(candidate.email) },
      to_remove: stale_recipients(eligible).size }
  end

  private

  def syncable?
    @link.present? && (@campaign.draft? || @campaign.scheduled?) && !@campaign.email_campaign_recipients.where.not(sent_at: nil).exists?
  end

  def remove_stale(eligible)
    EmailCampaignRecipient.where(id: stale_recipients(eligible).map(&:id)).delete_all
  end

  # Pending, never sent, without events (the events subquery is limited to this campaign).
  def stale_recipients(eligible)
    recipients = @campaign.email_campaign_recipients
    with_events = EmailEvent.where(recipient_id: recipients.select(:id)).select(:recipient_id)
    recipients.pending.where(sent_at: nil).where.not(id: with_events).reject { |recipient| eligible.include?(recipient.email.downcase) }
  end

  def existing_emails
    @campaign.email_campaign_recipients.pluck(:email).to_set(&:downcase)
  end

  def add_missing(candidates)
    suppressed = EmailSuppression.suppressed_set_for(@campaign.account)
    existing = existing_emails
    rows = candidates.reject { |candidate| existing.include?(candidate.email) }.map { |candidate| recipient_attributes(candidate, suppressed) }
    # A concurrent writer may have added the same address: skip it (unique index), never raise.
    rows.each_slice(BATCH_SIZE).sum do |batch|
      EmailCampaignRecipient.insert_all(batch, unique_by: :idx_email_campaign_recipients_campaign_email).rows.size # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def recipient_attributes(candidate, suppressed)
    now = Time.current
    {
      email_campaign_id: @campaign.id, contact_id: candidate.contact.id, email: candidate.email,
      name: candidate.contact.name.presence, custom_data: custom_data(candidate),
      status: EmailCampaignRecipient.statuses[suppressed.include?(candidate.email) ? :suppressed : :pending],
      created_at: now, updated_at: now
    }
  end

  # Personalization of the journey (PRD §6.3): first name, company and the audience's extra
  # columns, under the keys of CampaignJourney::AudienceColumns (same as the spreadsheet import).
  def custom_data(candidate)
    values = candidate.row.extra_values.to_h
    extras = column_map.each_with_object({}) do |(key, header), data|
      data[key] = values[header].to_s unless RESERVED_KEYS.include?(key)
    end
    { 'primeiro_nome' => candidate.contact.name.to_s.split.first.to_s, 'empresa' => company_name(candidate) }.merge(extras)
  end

  def column_map
    @column_map ||= CampaignJourney::AudienceColumns.key_map(@link.campaign_import)
  end

  def company_name(candidate)
    candidate.contact.try(:company)&.name.presence || candidate.row.company_name.to_s
  end
end
