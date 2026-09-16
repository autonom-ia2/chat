class EmailCampaigns::UnsubscribeController < ApplicationController
  skip_before_action :authenticate_user!, raise: false
  skip_before_action :set_current_user, raise: false
  # CSRF intentionally skipped: RFC 8058 one-click POSTs come from mail providers without a
  # session/token. The unsubscribe token itself is the signed authorization.
  skip_before_action :verify_authenticity_token, raise: false

  layout false

  # Generic POST response: identical for valid, invalid or repeated tokens (no validity oracle).
  CONFIRMATION_TEXT = 'Descadastro confirmado. Você não receberá mais e-mails desta lista.'.freeze

  # GET /email_campaigns/u/:token — pt_BR landing with a confirm POST button. Invalid token
  # renders the same page with a generic message (always 200, never leaks token validity).
  def show
    @recipient = find_recipient if EmailCampaigns::Config.enabled?
    render :show
  end

  # POST /email_campaigns/u/:token — RFC 8058 one-click unsubscribe. Idempotent: suppression is
  # find-or-create, event/status only recorded on the first unsubscribe. Always 200 plain text.
  def create
    process_unsubscribe if EmailCampaigns::Config.enabled?
    render plain: CONFIRMATION_TEXT
  end

  private

  def find_recipient
    data = EmailCampaigns::Unsubscribe::Token.decode(params[:token])
    return if data.blank?

    EmailCampaignRecipient.find_by(id: data[:r] || data['r'])
  end

  def process_unsubscribe
    recipient = find_recipient
    return if recipient.nil?

    suppress!(recipient)
  rescue StandardError => e
    Rails.logger.warn("[EmailCampaigns::Unsubscribe#create] #{e.message}")
  end

  def suppress!(recipient)
    campaign = recipient.email_campaign
    recipient.with_lock do
      EmailCampaigns::SuppressionRegistry.new(account: campaign.account, email: recipient.email, campaign: campaign).block!(
        reason: 'unsubscribe', source: 'link', event_key: "unsubscribe:#{recipient.id}"
      )
      return if recipient.unsubscribed?

      recipient.email_events.create!(event_type: :unsubscribe, occurred_at: Time.current)
      # A verified opt-out must not be rolled back by unrelated legacy name/custom-data validators.
      recipient.update_columns(status: EmailCampaignRecipient.statuses[:unsubscribed], # rubocop:disable Rails/SkipsModelValidations
                               last_event_at: Time.current, updated_at: Time.current)
    end
    campaign.refresh_counters!
  end
end
