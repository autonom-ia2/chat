require 'digest'

# Públicos (#993, PRD B8 and §6.4): who in an audience does not receive, per channel, before
# any send. Works before and after saving because it compares the hashes stored on the rows:
# - WhatsApp: rows whose mobile belongs to a contact of the account that refused active
#   messages (#737, `opted_out_at`) or is blocked (chat#2733, `blocked`), with or without the
#   9th digit; refused and blocked at once counts as refused (each row in one reason);
# - e-mail: like the send (EmailCampaigns::DeliveryClaim), rows whose address belongs to a contact
#   of the account that refused (#737) or is blocked (chat#2733), then rows whose address is
#   suppressed in the account (EmailSuppression and blocking EmailSuppressionState), split into
#   unsubscribed, bounced and other suppressions; each row in one reason, in this order.
# `receive` = channel count − not receiving; a channel switched off receives nobody.
class CampaignImports::AudienceReachability
  ROW_STATUSES = %i[valid imported].freeze
  # Import statuses with validated rows (show adds reachability only for these).
  STATUSES = %w[ready_to_confirm queued importing completed completed_with_failures].freeze
  BOUNCE_REASONS = %w[hard_bounce].freeze
  UNSUBSCRIBE_REASONS = %w[unsubscribe].freeze

  def initialize(campaign_import)
    @campaign_import = campaign_import
    @account = campaign_import.account
  end

  # SMS (#1004) reaches the same mobiles as WhatsApp, with its own switch (absent = off).
  def perform
    whatsapp_result = whatsapp
    { 'whatsapp' => whatsapp_result, 'sms' => sms(whatsapp_result.slice('opted_out', 'blocked')), 'email' => email }
  end

  private

  def rows
    @campaign_import.campaign_import_rows.where(status: ROW_STATUSES)
  end

  def channel(name)
    @campaign_import.channels.to_h[name].to_h
  end

  def summary(name, excluded)
    total = channel(name)['count'].to_i
    not_receiving = excluded.values.sum
    receive = channel(name)['enabled'] == true ? [total - not_receiving, 0].max : 0
    { 'total' => total, 'receive' => receive }.merge(excluded)
  end

  def whatsapp
    opted_out = phone_hashes(@account.contacts.opted_out)
    blocked = phone_hashes(@account.contacts.campaign_unreachable.not_opted_out) - opted_out
    summary('whatsapp', 'opted_out' => phone_rows_count(opted_out), 'blocked' => phone_rows_count(blocked))
  end

  def sms(excluded)
    channels = CampaignJourney::AudienceContacts.with_sms_channel(@campaign_import.channels.to_h)
    total = channels.dig('sms', 'count').to_i
    receive = channels.dig('sms', 'enabled') == true ? [total - excluded.values.sum, 0].max : 0
    { 'total' => total, 'receive' => receive }.merge(excluded)
  end

  def phone_rows_count(hashes)
    hashes.empty? ? 0 : rows.where(normalized_phone_hash: hashes).count
  end

  def phone_hashes(contacts)
    matcher = CampaignImports::ContactMatcher.new(@account)
    contacts.where.not(phone_number: [nil, '']).pluck(:phone_number)
            .flat_map { |phone| matcher.candidates(phone) }
            .map { |phone| Digest::SHA256.hexdigest(phone) }.uniq
  end

  def email
    opted_out = email_hashes(@account.contacts.opted_out)
    blocked = email_hashes(@account.contacts.campaign_unreachable.not_opted_out) - opted_out
    refused = opted_out | blocked
    by_reason = { 'opted_out' => opted_out, 'blocked' => blocked }
                .merge(suppressed_hashes_by_reason.transform_values { |hashes| hashes - refused })
    summary('email', by_reason.transform_values { |hashes| email_rows_count(hashes) })
  end

  def email_rows_count(hashes)
    hashes.empty? ? 0 : rows.where(normalized_email_hash: hashes).count
  end

  # Hashes of the contacts' addresses, normalized like the rows (CampaignJourney::AudienceContacts).
  def email_hashes(contacts)
    contacts.where.not(email: [nil, '']).pluck(:email)
            .filter_map { |address| normalized_email(address) }
            .map { |address| Digest::SHA256.hexdigest(address) }.uniq
  end

  def normalized_email(address)
    EmailCampaigns::EmailNormalizer.normalize!(address).email
  rescue EmailCampaigns::EmailNormalizer::Error
    nil
  end

  # { 'unsubscribed' => [hash], 'bounced' => [hash], 'suppressed' => [hash] }; one bucket per address.
  def suppressed_hashes_by_reason
    buckets = { 'unsubscribed' => [], 'bounced' => [], 'suppressed' => [] }
    suppression_reasons.each do |address, reason|
      buckets[bucket_for(reason)] << Digest::SHA256.hexdigest(address)
    end
    buckets
  end

  def bucket_for(reason)
    return 'unsubscribed' if UNSUBSCRIBE_REASONS.include?(reason)
    return 'bounced' if BOUNCE_REASONS.include?(reason)

    'suppressed'
  end

  def suppression_reasons
    states = EmailSuppressionState.blocking.where(account_id: @account.id).pluck(:email, :reason)
    legacy = EmailSuppression.where(account_id: @account.id).pluck(:email, :reason)
    (states + legacy).to_h { |address, reason| [address.to_s.strip.downcase, reason.to_s] }
  end
end
