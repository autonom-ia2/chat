class EmailCampaigns::TenantProtectionRetirementJob < ApplicationJob
  queue_as :scheduled_jobs

  REPUTATION_CODES = %w[reputation_paused legacy_pause reputation_threshold].freeze
  LEGACY_ERROR_PREFIX = 'Envios pausados pelo guardrail de reputação da conta'.freeze

  def perform(account_id)
    return unless EmailCampaigns::Config.enabled?
    return unless Account.exists?(account_id)

    retirement_candidates(account_id).find_each do |campaign|
      campaign.resume!
    rescue CustomExceptions::EmailReputationBlocked
      # Hygiene/import/provider races remain authoritative.
      nil
    end
  end

  private

  def retirement_candidates(account_id)
    structured = EmailCampaign.where(account_id: account_id, status: :paused)
                              .where("pause_reason ->> 'kind' = ?", 'reputation')
                              .where("pause_reason ->> 'code' IN (?)", REPUTATION_CODES)
    legacy = EmailCampaign.where(account_id: account_id, status: :paused)
                          .where('last_error LIKE ?', "#{LEGACY_ERROR_PREFIX}%")
    structured.or(legacy)
  end
end
