class EmailCampaigns::RecipientPreflightJob < ApplicationJob
  queue_as :low
  BATCH_SIZE = 100
  DOMAIN_BUDGET = 10
  TIME_BUDGET = 10

  # Post-commit API for import, maintenance and an explicitly requested UI recheck.
  # Returns true for a newly queued pass; false coalesces live chains/no due work.
  def self.enqueue(campaign_id, recheck: false)
    return false unless EmailCampaigns::Config.enabled?

    campaign = EmailCampaign.find_by(id: campaign_id)
    return false unless campaign

    lease = EmailCampaigns::PreflightLease.new(campaign).acquire(recheck: recheck)
    return false unless lease

    ActiveRecord.after_all_transactions_commit { perform_later(campaign_id, *lease) }
    true
  end

  def self.due(scope = EmailCampaignRecipient.pending)
    unchecked = scope.where(preflight_status: 'unchecked')
    return unchecked unless EmailCampaigns::HygieneConfig.new.dns_enabled?

    unchecked.or(scope.where(preflight_reason_code: 'dns_disabled'))
             .or(scope.where('preflight_valid_until <= ?', Time.current))
  end

  def perform(campaign_id, token = nil, cursor = 0)
    return unless EmailCampaigns::Config.enabled?

    campaign = EmailCampaign.find_by(id: campaign_id)
    return unless campaign

    @lease = EmailCampaigns::PreflightLease.new(campaign)
    config = EmailCampaigns::HygieneConfig.new
    check_transaction!(config)
    queued = token ? [token, cursor] : @lease.acquire
    return unless queued

    claimed = @lease.claim(*queued)
    return unless claimed

    cursor = process_batch(*claimed, config)
    finish_batch(campaign, claimed.first, cursor)
  end

  private

  def finish_batch(campaign, token, cursor)
    campaign.refresh_counters! if @counter_refresh_needed
    continuation = @lease.advance(token, cursor)
    ActiveRecord.after_all_transactions_commit { self.class.perform_later(campaign.id, *continuation) } if continuation
  end

  def check_transaction!(config)
    return unless config.dns_enabled? && ActiveRecord::Base.connection.transaction_open?

    raise 'recipient preflight DNS must run outside a database transaction'
  end

  def process_batch(token, cursor, config)
    domains = {}
    preflight = build_preflight(config, domains)
    initial_cursor = cursor
    deadline = monotonic + TIME_BUDGET
    @lease.remaining(cursor).order(:id).limit(BATCH_SIZE).each do |recipient|
      break if cursor > initial_cursor && (monotonic >= deadline || domains.size >= DOMAIN_BUDGET)

      result = preflight.call(recipient.email)
      persist_result(recipient, result, token, config)
      cursor = recipient.id
    end
    cursor
  end

  def build_preflight(config, domains)
    validator = EmailCampaigns::DomainValidator.new(resolver: EmailCampaigns::Dns::MailRouteResolver.new, cache: Rails.cache) if config.dns_enabled?
    lookup = ->(domain) { domains[domain] ||= validator.call(domain) } if validator
    EmailCampaigns::AddressPreflight.new(validator: lookup)
  end

  def persist_result(recipient, result, token, config)
    attributes = { preflight_status: result.fetch(:status), preflight_reason_code: result.fetch(:reason_code),
                   preflight_suggestion: result[:suggestion], preflight_checked_at: Time.current,
                   preflight_valid_until: result.fetch(:valid_until), updated_at: Time.current }
    # Deterministic findings exclude this campaign row only; retain the evidence
    # and never create a tenant suppression or silently repair the address.
    attributes[:status] = :suppressed if config.enforce? && %w[invalid review].include?(result.fetch(:status))

    # Compare-and-set plus fencing token: stale network responses cannot update a
    # newer pass, dispatched history, or a recipient changed by another writer.
    @lease.with_holder(token) do
      updated = EmailCampaignRecipient.where(id: recipient.id, status: :pending,
                                             preflight_checked_at: recipient.preflight_checked_at)
                                      .update_all(attributes) # rubocop:disable Rails/SkipsModelValidations
      @counter_refresh_needed = true if updated.positive? && attributes.key?(:status)
    end
  end

  def monotonic
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
