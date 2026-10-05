require 'digest'

# Públicos (#993, PRD B8 and §6.4): who in an audience does not receive, per channel, before
# any send. Works before and after saving because it compares the hashes stored on the rows:
# - WhatsApp: rows whose mobile belongs to a contact of the account that refused active
#   messages (#737, `opted_out_at`), with or without the 9th digit;
# - e-mail: rows whose address is suppressed in the account (EmailSuppression and blocking
#   EmailSuppressionState), split into unsubscribed, bounced and other suppressions.
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

  def perform
    { 'whatsapp' => whatsapp, 'email' => email }
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
    hashes = opted_out_phone_hashes
    opted_out = hashes.empty? ? 0 : rows.where(normalized_phone_hash: hashes).count
    summary('whatsapp', 'opted_out' => opted_out)
  end

  def opted_out_phone_hashes
    matcher = CampaignImports::ContactMatcher.new(@account)
    @account.contacts.where.not(opted_out_at: nil).where.not(phone_number: [nil, '']).pluck(:phone_number)
            .flat_map { |phone| matcher.candidates(phone) }
            .map { |phone| Digest::SHA256.hexdigest(phone) }.uniq
  end

  def email
    by_reason = suppressed_hashes_by_reason
    counts = by_reason.transform_values { |hashes| hashes.empty? ? 0 : rows.where(normalized_email_hash: hashes).count }
    summary('email', counts)
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
