# Públicos (#1005, acceptance F1): links old WhatsApp campaigns to the old imports they used,
# through the import's hidden base label (campaign.audience label ids → campaign_import_labels
# of kind base). Idempotent: a campaign that already has a link is left alone.
#
# Only completed campaigns are linked: a linked campaign sends to the audience list instead of
# the labels, so linking a campaign that has not sent yet would change who receives it (N3).
# Campaigns whose labels point to more than one import are left out (ambiguous), and so are campaigns sent to
# the base label plus other labels (extra_labels): they did not reach the whole import (#990 review).
class CampaignJourney::AudienceLinkBackfill
  COUNTERS = %i[campaigns_with_labels linked already_linked no_import ambiguous extra_labels not_completed].freeze

  def initialize(apply: false)
    @apply = apply
    @counts = COUNTERS.index_with(0)
  end

  def perform
    Campaign.one_off.where.not(audience: nil).find_each { |campaign| visit(campaign) }
    @counts
  end

  private

  def visit(campaign)
    label_ids = Array(campaign.audience).filter_map { |item| item['id'].to_i if item.is_a?(Hash) && item['type'] == 'Label' }
    return if label_ids.empty?

    @counts[:campaigns_with_labels] += 1
    import_ids = label_ids.flat_map { |label_id| base_label_index[[campaign.account_id, label_id]] }.compact.uniq
    outcome = outcome_for(campaign, import_ids, extra_labels: label_ids.uniq.size > base_label_count(campaign, label_ids))
    @counts[outcome] += 1
    link!(campaign, import_ids.first) if outcome == :linked
  end

  def outcome_for(campaign, import_ids, extra_labels:)
    return :already_linked if CampaignAudienceLink.for_campaign(campaign)
    return :no_import if import_ids.empty?
    return :ambiguous if import_ids.size > 1
    return :extra_labels if extra_labels

    campaign.completed? ? :linked : :not_completed
  end

  def base_label_count(campaign, label_ids)
    label_ids.uniq.count { |label_id| base_label_index.key?([campaign.account_id, label_id]) }
  end

  def link!(campaign, campaign_import_id)
    return unless @apply

    CampaignAudienceLink.create!(account_id: campaign.account_id, campaign: campaign, campaign_import_id: campaign_import_id)
  end

  # [account_id, label_id] => [campaign_import_id, ...]
  def base_label_index
    @base_label_index ||= CampaignImportLabel.kind_base.where.not(label_id: nil).joins(:campaign_import)
                                             .pluck('campaign_imports.account_id', :label_id, :campaign_import_id)
                                             .group_by { |account_id, label_id, _| [account_id, label_id] }
                                             .transform_values { |rows| rows.map(&:last) }
  end
end
