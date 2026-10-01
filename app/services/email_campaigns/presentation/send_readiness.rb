# Read-only review of the same prerequisites used by campaign admission.
# Global SES protection is authoritative; tenant reputation is diagnostic.
class EmailCampaigns::Presentation::SendReadiness
  def initialize(campaign)
    @campaign = campaign
  end

  def call
    state = EmailCampaigns::Reports::RecipientState.new(@campaign)
    candidates = state.resume_candidates
    candidates = candidates.where(id: state.ready_ids) if EmailCampaigns::HygieneConfig.new.enforce?
    eligible = candidates.count
    checks = send_checks(eligible)
    { can_send: (@campaign.draft? || @campaign.scheduled?) && checks.values.all?, checks: checks,
      eligible_recipients: eligible, protected_recipients: @campaign.email_campaign_recipients.where(sent_at: nil, id: state.protected_ids).count }
  end

  private

  def send_checks(eligible)
    {
      subject: @campaign.subject.present?, content: @campaign.body_html.present?,
      sender: @campaign.sender_ready?, recipients: eligible.positive?,
      import: !@campaign.recipient_import_active?, hygiene: EmailCampaigns::PreflightDecision.new.campaign_allowed?(@campaign),
      provider: EmailCampaigns::Guardrail.protection(@campaign.account, delivery_mode: @campaign.delivery_mode).nil?
    }
  end
end
