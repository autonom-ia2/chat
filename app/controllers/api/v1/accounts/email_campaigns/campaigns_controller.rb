class Api::V1::Accounts::EmailCampaigns::CampaignsController < Api::V1::Accounts::EmailCampaigns::BaseController
  rescue_from CustomExceptions::EmailReputationBlocked do |error|
    render json: { error: 'email_campaign.protected', protection: EmailCampaigns::Presentation::Errors.protection(error.protection) },
           status: :unprocessable_entity
  end

  helper_method :campaign_presentation

  before_action :fetch_campaign,
                only: [:show, :update, :destroy, :send_now, :schedule, :pause, :resume, :cancel, :duplicate, :reevaluate, :recheck]
  before_action :validate_hygiene_configuration, only: [:resume, :reevaluate, :recheck]

  def index
    authorize EmailCampaign
    query = EmailCampaigns::CampaignQuery.new(account: Current.account, params: report_filter_params(%w[status campaign_status q since until]))
    @campaigns = query.call.includes(:sender_identity, latest_recipient_import: :source_file_attachment)
    @campaign_presenter = EmailCampaigns::Presentation::Campaign.new(account: Current.account, actor: Current.user, campaigns: @campaigns.to_a)
  end

  def show; end

  def create
    @campaign = campaign_scope.new(campaign_params)
    authorize @campaign
    @campaign.ses_configuration_set = @campaign.sender_identity&.ses_configuration_set
    @campaign.save!
    render_campaign(status: :created)
  end

  def update
    return render_unprocessable('email_campaign.not_editable') unless @campaign.draft?

    @campaign.assign_attributes(campaign_params)
    @campaign.ses_configuration_set = @campaign.sender_identity&.ses_configuration_set if @campaign.sender_identity_id_changed?
    @campaign.save!
    render_campaign
  end

  def destroy
    @campaign.with_delivery_lock do
      return render_unprocessable('import_in_progress') if @campaign.recipient_import_active?
      return render_unprocessable('email_campaign.delivery_history_retained') if @campaign.delivery_history?

      EmailEvent.where(recipient_id: @campaign.email_campaign_recipients.select(:id)).delete_all
      @campaign.email_campaign_recipients.delete_all
      @campaign.destroy!
    end
    head :no_content
  end

  def send_now
    protection = ::EmailCampaigns::Guardrail.protection(Current.account, delivery_mode: @campaign.delivery_mode)
    return render json: { error: 'email_campaign.protected', protection: protection }, status: :unprocessable_entity if protection

    return render_unprocessable('email_campaign.not_sendable') unless @campaign.sendable?
    return render_unprocessable('email_campaign.not_sendable') unless @campaign.claim_for_sending!

    EmailCampaigns::DeliveryJob.perform_later(@campaign.id)
    render_campaign
  end

  def schedule
    return render_unprocessable('email_campaign.scheduled_at_required') if params[:scheduled_at].blank?

    return render_unprocessable('email_campaign.not_sendable') unless @campaign.schedule!(scheduled_at: params[:scheduled_at])

    render_campaign
  end

  def pause
    @campaign.pause!
    render_campaign
  end

  def resume
    state = EmailCampaigns::Reports::RecipientState.new(@campaign)
    candidates = state.resume_candidates
    candidates = candidates.where(id: state.ready_ids) if EmailCampaigns::Presentation::Configuration.hygiene.enforce?
    return render_unprocessable('email_campaign.not_sendable') unless candidates.exists?
    return render_unprocessable('email_campaign.not_sendable') unless @campaign.resume!(actor: Current.user)

    render_campaign
  end

  def reevaluate
    ::EmailCampaigns::Guardrail.reevaluate!(Current.account, delivery_mode: @campaign.delivery_mode)
    render_campaign
  end

  def recheck
    return render_unprocessable('import_in_progress') if @campaign.recipient_import_active?
    return render_unprocessable('email_campaign.not_editable') if @campaign.terminal?

    # enqueue owns account -> state -> campaign locking and coalesces a live pass.
    EmailCampaigns::RecipientPreflightJob.enqueue(@campaign.id, recheck: true)
    @campaign.reload
    return render_unprocessable('import_in_progress') if @campaign.recipient_import_active?
    return render_unprocessable('email_campaign.not_editable') if @campaign.terminal?

    render_campaign(status: :accepted)
  end

  def cancel
    return render_unprocessable('import_in_progress') if @campaign.cancel! == false

    render_campaign
  end

  def duplicate
    source = @campaign
    @campaign = campaign_scope.new(
      name: "#{source.name} (cópia)",
      subject: source.subject,
      preheader: source.preheader,
      from_name: source.from_name,
      from_email: source.from_email,
      reply_to: source.reply_to,
      delivery_mode: source.delivery_mode,
      sender_identity: source.sender_identity,
      sender_inbox: source.sender_inbox,
      body_mjml: source.body_mjml,
      body_html: source.body_html,
      status: :draft
    )
    authorize @campaign, :create?
    @campaign.ses_configuration_set = @campaign.sender_identity&.ses_configuration_set
    @campaign.save!
    render_campaign(status: :created)
  end

  private

  def campaign_presentation(campaign)
    @campaign_presenter ||= EmailCampaigns::Presentation::Campaign.new(account: Current.account, actor: Current.user)
    @campaign_presenter.call(campaign)
  end

  def render_campaign(status: :ok)
    @campaign.reload
    Current.account.reload
    @campaign_presenter = nil
    render :show, status: status
  end

  def campaign_scope
    EmailCampaign.where(account: Current.account)
  end

  def fetch_campaign
    @campaign = campaign_scope.find(params[:id])
    authorize @campaign
  end

  def campaign_params
    params.require(:email_campaign)
          .permit(:name, :subject, :from_name, :body_html, :reply_to, :sender_identity_id,
                  :body_mjml, :preheader, :from_email, :delivery_mode, :sender_inbox_id)
  end

  def render_unprocessable(code)
    render json: { error: code }, status: :unprocessable_entity
  end
end
