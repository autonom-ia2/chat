# Request-local aggregates over an already authorized campaign collection. Exposes
# the recipient scope consumed by RecipientState and PreflightDecision, without
# loading recipients, events or account-wide suppression sets.
class EmailCampaigns::Presentation::CampaignBatch
  attr_reader :account, :membership, :email_campaign_recipients

  delegate :id, to: :account, prefix: true

  def initialize(account:, actor:, campaigns:)
    raise ArgumentError, 'campaign account mismatch' if campaigns.any? { |campaign| campaign.account_id != account.id }

    @account = account
    @campaign_ids = campaigns.map(&:id)
    @membership = account.account_users.find_by(user_id: actor.id) if actor
    @email_campaign_recipients = EmailCampaignRecipient.where(email_campaign_id: @campaign_ids)
    @state = EmailCampaigns::Reports::RecipientState.new(self)
  end

  def unsent_counts(campaign)
    @unsent_counts ||= email_campaign_recipients.where(sent_at: nil).group(:email_campaign_id, @state.unsent_classification)
                                                .count.each_with_object({}) do |((id, classification), count), result|
      (result[id] ||= {})[classification] = count
    end
    @unsent_counts.fetch(campaign.id, {})
  end

  def historical_sent(campaign)
    @historical_sent ||= email_campaign_recipients.where.not(sent_at: nil).group(:email_campaign_id).count
    @historical_sent.fetch(campaign.id, 0)
  end

  def issues_count(campaign)
    @issues_count ||= EmailCampaignImportIssue.where(email_campaign_id: @campaign_ids).group(:email_campaign_id).count
    @issues_count.fetch(campaign.id, 0)
  end

  def import_active?(campaign)
    @active_import_ids ||= EmailCampaignImport.active.where(email_campaign_id: @campaign_ids).distinct.pluck(:email_campaign_id).to_set
    @active_import_ids.include?(campaign.id)
  end

  def resume_candidate?(campaign, config)
    @candidate_ids ||= begin
      candidates = @state.resume_candidates
      candidates = candidates.where(id: @state.ready_ids) if config.enforce?
      candidates.distinct.pluck(:email_campaign_id).to_set
    end
    @candidate_ids.include?(campaign.id)
  end

  def unresolved?(campaign, config)
    @unresolved_ids ||= EmailCampaigns::PreflightDecision.new(config: config).unresolved(self)
                                                         .where.not(id: @state.protected_ids).distinct.pluck(:email_campaign_id).to_set
    @unresolved_ids.include?(campaign.id)
  end
end
