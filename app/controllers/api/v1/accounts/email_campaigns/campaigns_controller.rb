class Api::V1::Accounts::EmailCampaigns::CampaignsController < Api::V1::Accounts::EmailCampaigns::BaseController
  before_action :fetch_campaign,
                only: [:show, :update, :destroy, :send_now, :schedule, :pause, :resume, :cancel, :duplicate]

  def index
    authorize EmailCampaign
    @campaigns = campaign_scope.includes(:sender_identity, latest_recipient_import: :source_file_attachment).order(created_at: :desc)
  end

  def show; end

  def create
    @campaign = campaign_scope.new(campaign_params)
    authorize @campaign
    @campaign.ses_configuration_set = @campaign.sender_identity&.ses_configuration_set
    @campaign.save!
    render :show, status: :created
  end

  def update
    return render_unprocessable('email_campaign.not_editable') unless @campaign.draft?

    @campaign.assign_attributes(campaign_params)
    @campaign.ses_configuration_set = @campaign.sender_identity&.ses_configuration_set if @campaign.sender_identity_id_changed?
    @campaign.save!
    render :show
  end

  def destroy
    @campaign.with_lock do
      return render_unprocessable('import_in_progress') if @campaign.recipient_import_active?

      EmailEvent.where(recipient_id: @campaign.email_campaign_recipients.select(:id)).delete_all
      @campaign.email_campaign_recipients.delete_all
      @campaign.destroy!
    end
    head :no_content
  end

  def send_now
    return render_unprocessable('email_campaign.not_sendable') unless @campaign.sendable?
    return render_unprocessable('email_campaign.not_sendable') unless @campaign.claim_for_sending!

    EmailCampaigns::DeliveryJob.perform_later(@campaign.id)
    render :show
  end

  def schedule
    return render_unprocessable('email_campaign.scheduled_at_required') if params[:scheduled_at].blank?

    @campaign.with_lock do
      return render_unprocessable('email_campaign.not_sendable') unless @campaign.sendable?

      @campaign.update!(status: :scheduled, scheduled_at: params[:scheduled_at])
    end
    render :show
  end

  def pause
    @campaign.pause!
    render :show
  end

  def resume
    @campaign.resume!
    render :show
  end

  def cancel
    @campaign.with_lock do
      return render_unprocessable('import_in_progress') if @campaign.recipient_import_active?

      @campaign.cancel!
    end
    render :show
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
    render :show, status: :created
  end

  private

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
