# Test send (PRD §6.9, §8.9; acceptance D8, L5, L6). Renders with the first recipient as sample and
# an inert unsubscribe link, never creates a recipient or event (it does not count in the results),
# and goes out the same way the real send does: the verified domain (SES) or the campaign's inbox
# (direct_inbox), with the same Reply-To.
#
# Without `to_email` the test goes to the logged-in user's own email ("Enviar teste para mim");
# the editor may still pass `to_email`.
class Api::V1::Accounts::EmailCampaigns::TestSendsController < Api::V1::Accounts::EmailCampaigns::BaseController
  def create
    campaign = EmailCampaign.where(account: Current.account).find(params[:id])
    authorize campaign, :update?

    to_email = (params[:to_email].presence || Current.user.email).to_s.strip
    return render_unprocessable('email_campaign.invalid_email') unless Devise.email_regexp.match?(to_email)
    return render_unprocessable(missing_sender_code(campaign)) unless campaign.sender_ready?

    render json: { message_id: deliver(campaign, to_email), to_email: to_email }
  rescue EmailCampaigns::Ses::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue DirectSendFailed
    render_unprocessable('email_campaign.test_send_failed')
  end

  private

  DirectSendFailed = Class.new(StandardError)

  def deliver(campaign, to_email)
    renderer = EmailCampaigns::TemplateRenderer.new(sample_recipient(campaign, to_email), inert_unsubscribe: true)
    return deliver_direct(campaign, to_email, renderer) if campaign.direct_inbox?

    EmailCampaigns::Ses::Sender.new(campaign.sender_identity).deliver(
      to: to_email,
      subject: renderer.render(campaign.subject),
      html_body: inject_preheader(renderer.render(campaign.body_html), renderer.render(campaign.preheader)),
      reply_to: EmailCampaigns::ReplyTo.for(campaign),
      from_email: from_email(campaign)
    )
  end

  # Same rendering as EmailCampaigns::DirectInbox::RecipientSender, through the campaign's inbox.
  def deliver_direct(campaign, to_email, renderer)
    EmailCampaigns::DirectInbox::Sender.new(campaign.sender_inbox).deliver(
      to: to_email, subject: renderer.render(campaign.subject), html_body: renderer.render(campaign.body_html),
      from_email: campaign.from_email, reply_to: EmailCampaigns::ReplyTo.for(campaign)
    )
  rescue StandardError => e
    Rails.logger.error("[EmailCampaigns::TestSendsController] direct test send failed campaign=#{campaign.id} #{e.class.name}")
    raise DirectSendFailed
  end

  def missing_sender_code(campaign)
    campaign.direct_inbox? ? 'email_campaign.sender_inbox_missing' : 'email_campaign.sender_identity_missing'
  end

  # Render with the first real recipient (real custom_data drops) or a fake in-memory one.
  def sample_recipient(campaign, to_email)
    campaign.email_campaign_recipients.order(:id).first ||
      campaign.email_campaign_recipients.new(name: 'Contato Teste', email: to_email)
  end

  # Inject a hidden preheader snippet right after <body> (or at the top of the html) so the test
  # send mirrors the real send's inbox preview text. Text is rendered via TemplateRenderer.
  def inject_preheader(html, preheader)
    return html if preheader.blank?

    snippet = '<div style="display:none;visibility:hidden;max-height:0;overflow:hidden;mso-hide:all;' \
              "font-size:0;line-height:0;color:transparent;\">#{preheader}#{'&zwnj;&nbsp;' * 60}</div>"
    if html =~ /<body[^>]*>/i
      html.sub(/(<body[^>]*>)/i) { "#{Regexp.last_match(1)}#{snippet}" }
    else
      snippet + html
    end
  end

  def from_email(campaign)
    name = campaign.from_name.presence
    addr = campaign.from_email.presence || campaign.sender_identity.from_email.presence
    addr.present? && name.present? ? "#{name} <#{addr}>" : addr
  end

  def render_unprocessable(code)
    render json: { error: code }, status: :unprocessable_entity
  end
end
