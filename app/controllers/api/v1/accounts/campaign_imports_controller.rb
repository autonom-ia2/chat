class Api::V1::Accounts::CampaignImportsController < Api::V1::Accounts::BaseController
  before_action :ensure_campaign_import_enabled
  before_action :set_current_page, only: [:index]
  before_action :fetch_campaign_import, only: [:show, :destroy, :confirm, :undo_labels, :download]
  before_action :check_authorization

  RESULTS_PER_PAGE = 25

  def index
    @campaign_imports = Current.account.campaign_imports
                                       .includes(:user, :campaign_import_labels)
                                       .order(created_at: :desc)
                                       .page(@current_page)
                                       .per(RESULTS_PER_PAGE)
    @campaign_imports_count = Current.account.campaign_imports.count
  end

  def create
    return render_bad_request('campaign_import.import_file_required') if params[:import_file].blank?
    return render_bad_request('campaign_import.file_too_large') if params[:import_file].size > CampaignImports::Config.max_file_size_bytes

    @campaign_import = build_campaign_import
    @campaign_import.original_file.attach(params[:import_file])
    CampaignImports::ValidateJob.perform_later(@campaign_import) if CampaignImports::Config.enabled?

    render :show, status: :created
  end

  def show; end

  def destroy
    deleted = false
    error_code = nil

    @campaign_import.with_lock do
      @campaign_import.reload
      unless @campaign_import.deletable_before_import?
        error_code = 'campaign_import.delete_not_available'
        next
      end

      @campaign_import.destroy!
      deleted = true
    end

    return render_bad_request(error_code) unless deleted

    head :no_content
  end

  def confirm
    should_enqueue = false
    error_code = nil
    @campaign_import.with_lock do
      @campaign_import.reload
      unless @campaign_import.ready_to_confirm?
        error_code = 'campaign_import.not_ready'
        next
      end

      @campaign_import.update!(status: :queued, confirmed_at: Time.current, queued_at: Time.current)
      should_enqueue = true
    end

    return render_bad_request(error_code) if error_code

    CampaignImports::ImportJob.perform_later(@campaign_import) if should_enqueue && CampaignImports::Config.enabled?

    render :show
  end

  def undo_labels
    should_enqueue = false
    already_done = false
    error_code = nil
    @campaign_import.with_lock do
      @campaign_import.reload
      if @campaign_import.undoing_labels? || @campaign_import.labels_undone?
        already_done = true
        next
      end

      unless @campaign_import.completed? || @campaign_import.completed_with_failures?
        error_code = 'campaign_import.undo_not_available'
        next
      end

      @campaign_import.update!(status: :undoing_labels, undo_status: :processing, undo_started_at: Time.current)
      should_enqueue = true
    end

    return render_bad_request(error_code) if error_code
    return render :show if already_done

    CampaignImports::UndoLabelsJob.perform_later(@campaign_import) if should_enqueue && CampaignImports::Config.enabled?

    render :show
  end

  def download
    attachment = attachment_for(params[:file])
    return render_bad_request('campaign_import.download_not_available') unless attachment&.attached?

    blob = attachment.blob
    send_data attachment.download,
              filename: blob.filename.to_s,
              type: blob.content_type || 'application/octet-stream',
              disposition: 'attachment'
  end

  private

  def ensure_campaign_import_enabled
    render json: { error: 'campaign_import.disabled' }, status: :not_found unless CampaignImports::Config.enabled?
  end

  def fetch_campaign_import
    @campaign_import = Current.account.campaign_imports
                                      .includes(:user, :campaign_import_labels)
                                      .find(params[:id])
  end

  def set_current_page
    @current_page = params[:page] || 1
  end

  # A `name` makes it a Públicos (#992) audience: one base label, columns read by SpreadsheetReader.
  def build_campaign_import
    return build_audience_import if campaign_import_params[:name].present?

    Current.account.campaign_imports.create!(
      user: Current.user,
      status: :uploaded,
      mode: 'batches',
      campaign_name: campaign_import_params[:campaign_name],
      batch_count: normalized_batch_count,
      options: campaign_import_options,
      **source_file_attributes
    )
  end

  def source_file_attributes
    file = params[:import_file]
    {
      source_filename: file.original_filename, source_content_type: file.content_type, source_byte_size: file.size,
      source_format: File.extname(file.original_filename.to_s).delete('.').downcase
    }
  end

  def build_audience_import
    name = campaign_import_params[:name].to_s.strip.first(255)
    Current.account.campaign_imports.create!(
      user: Current.user, status: :uploaded, mode: 'single_label', name: name, campaign_name: name, batch_count: 1,
      options: { default_country: 'BR', flow: CampaignImport::AUDIENCE_FLOW }, **source_file_attributes
    )
  end

  def campaign_import_params
    params.permit(:campaign_name, :batch_count, :name)
  end

  def normalized_batch_count
    count = campaign_import_params[:batch_count].to_i
    count.positive? ? count : 1
  end

  def campaign_import_options
    {
      default_country: 'BR',
      requested_batch_count: normalized_batch_count
    }
  end

  def attachment_for(kind)
    {
      'original' => @campaign_import.original_file,
      'normalized_csv' => @campaign_import.normalized_csv,
      'error_csv' => @campaign_import.error_csv,
      'report_csv' => @campaign_import.report_csv
    }[kind.to_s]
  end

  def render_bad_request(code)
    render json: { error: code }, status: :unprocessable_entity
  end
end
