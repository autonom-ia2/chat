# Test send (PRD §6.9, §8.9; acceptance D8, L5, L6). Renders with the first recipient as sample and
# an inert unsubscribe link, never creates a recipient or event (it does not count in the results),
# and goes out the same way the real send does: the verified domain (SES) or the campaign's inbox
# (direct_inbox), with the same Reply-To.
#
# Who sends: only who manages campaigns (`update?` → campaign_manage). To whom (#1093, decision of
# 07/10/2026): up to 5 typed addresses (`to_emails`, or the single `to_email`); none → the
# logged-in user's own address. Every address is checked before anything leaves: a valid e-mail,
# not suppressed, not a contact who refused messages. The limit of 10 per hour per user and
# campaign counts test sends (one request), not addresses: at most 50 e-mails an hour.
class Api::V1::Accounts::EmailCampaigns::TestSendsController < Api::V1::Accounts::EmailCampaigns::BaseController
  def create
    campaign = EmailCampaign.where(account: Current.account).find(params[:id])
    authorize campaign, :update?

    to_emails = requested_addresses
    refusal = address_refusal(campaign, to_emails) || sender_refusal(campaign)
    return render json: refusal, status: :unprocessable_entity if refusal
    return render json: { error: 'email_campaign.test_send_rate_limited' }, status: :too_many_requests if rate_limited?(campaign)

    message_ids = to_emails.map { |to_email| deliver(campaign, to_email) }
    render json: { message_id: message_ids.first, to_email: to_emails.first, message_ids: message_ids, to_emails: to_emails }
  rescue EmailCampaigns::Ses::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue DirectSendFailed
    render_unprocessable('email_campaign.test_send_failed')
  end

  private

  DirectSendFailed = Class.new(StandardError)
  # #999 review B7: at most this many test sends per user and campaign in a rolling hour.
  RATE_LIMIT = 10
  RATE_PERIOD = 1.hour

  def rate_limited?(campaign)
    key = "email_campaign_test_send:#{Current.user.id}:#{campaign.id}"
    count = Redis::Alfred.incr(key)
    Redis::Alfred.expire(key, RATE_PERIOD.to_i) if count == 1
    count > RATE_LIMIT
  end

  def deliver(campaign, to_email)
    renderer = EmailCampaigns::TemplateRenderer.new(sample_recipient(campaign, to_email), inert_unsubscribe: true)
    return deliver_direct(campaign, to_email, renderer) if campaign.direct_inbox?

    EmailCampaigns::Ses::Sender.new(campaign.sender_identity).deliver(
      to: to_email,
      subject: renderer.render(campaign.subject),
      html_body: inject_preheader(renderer.render(campaign.body_html, html: true), renderer.render(campaign.preheader, html: true)),
      reply_to: EmailCampaigns::ReplyTo.for(campaign),
      from_email: from_email(campaign)
    )
  end

  # Same rendering as EmailCampaigns::DirectInbox::RecipientSender, through the campaign's inbox.
  def deliver_direct(campaign, to_email, renderer)
    EmailCampaigns::DirectInbox::Sender.new(campaign.sender_inbox).deliver(
      to: to_email, subject: renderer.render(campaign.subject), html_body: renderer.render(campaign.body_html, html: true),
      from_email: campaign.from_email, reply_to: EmailCampaigns::ReplyTo.for(campaign)
    )
  rescue StandardError => e
    Rails.logger.error("[EmailCampaigns::TestSendsController] direct test send failed campaign=#{campaign.id} #{e.class.name}")
    raise DirectSendFailed
  end

  MAX_RECIPIENTS = 5

  # Typed addresses, trimmed and without repeats (case-insensitive); none → the user's own address.
  def requested_addresses
    permitted = params.permit(:to_email, to_emails: [])
    typed = [*permitted[:to_emails], permitted[:to_email]].map { |email| email.to_s.strip }.compact_blank
    typed = [Current.user.email.to_s.strip].compact_blank if typed.empty?
    typed.uniq(&:downcase)
  end

  def address_refusal(campaign, to_emails)
    return { error: 'email_campaign.test_send_no_recipient' } if to_emails.empty?
    return { error: 'email_campaign.test_send_too_many', limit: MAX_RECIPIENTS } if to_emails.size > MAX_RECIPIENTS

    invalid = to_emails.find { |email| !Devise.email_regexp.match?(email) }
    return { error: 'email_campaign.invalid_email', email: invalid } if invalid

    refused = to_emails.find { |email| campaign.refuses_address?(email) }
    { error: 'email_campaign.test_send_suppressed', email: refused.downcase } if refused
  end

  def sender_refusal(campaign)
    return if campaign.sender_ready?

    { error: campaign.direct_inbox? ? 'email_campaign.sender_inbox_missing' : 'email_campaign.sender_identity_missing' }
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
