class EmailCampaigns::DirectInbox::TickJob < ApplicationJob
  queue_as :low

  # Um "tick" = envia 1 destinatário e reagenda o próximo (o throttle vive no engine).
  def perform(campaign_id)
    return unless EmailCampaigns::Config.enabled?

    campaign = EmailCampaign.find_by(id: campaign_id)
    return if campaign.blank?

    eligible = campaign.with_delivery_lock do
      next false unless eligible_for_tick?(campaign)
      next false if campaign.recipient_import_active?

      campaign.update!(status: :sending) if campaign.scheduled?
      true
    end
    return unless eligible

    ActiveRecord.after_all_transactions_commit { EmailCampaigns::DirectInbox::DeliveryEngine.new(campaign).tick }
  end

  private

  def eligible_for_tick?(campaign)
    campaign.direct_inbox? && (campaign.sending? ||
      (campaign.scheduled? && campaign.scheduled_at.present? && campaign.scheduled_at <= Time.current))
  end
end
