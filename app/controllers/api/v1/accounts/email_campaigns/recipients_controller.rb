class Api::V1::Accounts::EmailCampaigns::RecipientsController < Api::V1::Accounts::EmailCampaigns::BaseController
  before_action :fetch_campaign
  before_action :set_current_page, only: [:index]

  RESULTS_PER_PAGE = 50

  def index
    @recipients = @campaign.email_campaign_recipients
                           .order(:id)
                           .page(@current_page).per(RESULTS_PER_PAGE)
    @recipients_count = @campaign.email_campaign_recipients.count
  end

  def create
    file = params[:import_file]
    return render_unprocessable('email_campaign.import_file_required') if file.blank?
    return render_unprocessable('email_campaign.file_too_large') if too_large?
    return render_unprocessable('unsupported_file_format') unless CampaignImports::Config.supported_formats.include?(
      File.extname(file.original_filename).delete('.').downcase
    )

    persist_upload(file)
    return if performed?

    enqueue_import
  end

  def retry_import
    @campaign.with_delivery_lock do
      return render_unprocessable('email_campaign.not_editable') unless @campaign.draft?
      return render_unprocessable('import_in_progress') if @campaign.recipient_import_active?

      @import = @campaign.email_campaign_imports.order(id: :desc).first
      return render_unprocessable('file_expired') unless @import&.retryable?

      @import.update!(status: :queued, result: {}, error_code: nil, completed_at: nil)
    end
    enqueue_import
  end

  private

  def persist_upload(file)
    @campaign.with_delivery_lock do
      return render_unprocessable('email_campaign.not_editable') unless @campaign.draft?
      return render_unprocessable('import_in_progress') if @campaign.recipient_import_active?

      @import = @campaign.email_campaign_imports.create!
      @import.source_file.attach(io: file, filename: file.original_filename, identify: false)
    end
  rescue StandardError => e
    fail_upload(e)
  end

  def fail_upload(error)
    # ActiveStorage uploads after commit. A storage error can leave a queued
    # record whose blob was never uploaded; release admission immediately.
    raise error unless @import && EmailCampaignImport.exists?(@import.id)

    @import.with_lock do
      @import.update!(status: :failed, error_code: 'upload_failed', completed_at: Time.current)
    end
    Rails.logger.error("[EmailCampaigns::RecipientsController] upload_error_class=#{error.class.name}")
    render json: { error: 'upload_failed' }, status: :service_unavailable
  end

  def enqueue_import
    # The persisted queued record is the outbox: maintenance recovers a failed
    # enqueue without asking the client to upload a second copy.
    begin
      EmailCampaigns::RecipientImportJob.perform_later(@import.id)
    rescue StandardError => e
      Rails.logger.error("[EmailCampaigns::RecipientsController] enqueue_error_class=#{e.class.name}")
    end
    @campaign.reload
    @recipients = []
    @recipients_count = @campaign.recipients_count
    @current_page = 1
    render :index, status: :accepted
  end

  def fetch_campaign
    @campaign = EmailCampaign.where(account: Current.account).find(params[:campaign_id])
    authorize @campaign, :show?
  end

  def too_large?
    params[:import_file].size > CampaignImports::Config.max_file_size_bytes
  end

  def set_current_page
    @current_page = params[:page] || 1
  end

  def render_unprocessable(code)
    render json: { error: code }, status: :unprocessable_entity
  end
end
