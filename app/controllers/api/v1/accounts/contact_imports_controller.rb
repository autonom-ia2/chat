# Importar contatos (#1006, PRD §8.7): the journey's contact import. Same reading, row checks,
# column choice and companies as Públicos, stored as a campaign_import with flow "contacts"
# that never shows as an audience. Extra columns become contact custom attributes.
# Permission is Chatwoot's contact import (ContactPolicy#import?: administrator or a custom role
# with contact_manage). Contract in docs/campaigns/publicos/contact-imports-1006.md.
class Api::V1::Accounts::ContactImportsController < Api::V1::Accounts::BaseController
  BOOLEAN_VALUES = %w[true false].freeze
  PROBLEM_ROWS_SHOWN = 20

  before_action :ensure_contact_import_enabled
  before_action -> { authorize(Contact, :import?) }
  before_action :fetch_contact_import, except: [:create]

  def show
    render_import
  end

  def create
    file = params[:import_file]
    return render_unprocessable('campaign_import.import_file_required') if file.blank?
    return render_unprocessable('campaign_import.file_too_large') if file.size > CampaignImports::Config.max_file_size_bytes

    @campaign_import = build_contact_import(file)
    @campaign_import.original_file.attach(file)
    CampaignImports::ValidateJob.perform_later(@campaign_import)
    render_import(status: :created)
  end

  # PATCH /contact_imports/:id/columns  { name:, phone:, email:, company: } (column index or null)
  def columns
    column_count = Array(@campaign_import.schema_resolution.to_h['columns']).size
    mapping = CampaignImports::ColumnChoice.new(params.permit(*CampaignImports::ColumnChoice::TARGETS), column_count: column_count).mapping
    return render_unprocessable('campaign_import.invalid_column_choice') unless mapping

    error_code = CampaignImports::DraftChanges.new(@campaign_import).choose_columns(mapping)
    return render_unprocessable(error_code) if error_code

    CampaignImports::ValidateJob.perform_later(@campaign_import)
    render_import
  end

  # PATCH /contact_imports/:id/companies  { create_companies: true | false } ("Criar e ligar")
  def companies
    value = params.permit(:create_companies)[:create_companies].to_s
    return render_unprocessable('campaign_import.invalid_companies_choice') unless BOOLEAN_VALUES.include?(value)

    error_code = CampaignImports::DraftChanges.new(@campaign_import).choose_companies(value == 'true')
    return render_unprocessable(error_code) if error_code

    render_import
  end

  # POST /contact_imports/:id/confirm — "Importar": contacts, companies and attributes are written.
  def confirm
    queued = false
    @campaign_import.with_lock do
      @campaign_import.reload
      next unless @campaign_import.ready_to_confirm?

      @campaign_import.update!(status: :queued, confirmed_at: Time.current, queued_at: Time.current)
      queued = true
    end
    return render_unprocessable('campaign_import.not_ready') unless queued

    CampaignImports::ImportJob.perform_later(@campaign_import)
    render_import
  end

  # A draft can be dropped; nothing was written to contacts yet.
  def destroy
    return render_unprocessable('campaign_import.delete_not_available') unless @campaign_import.deletable?

    @campaign_import.destroy!
    head :no_content
  end

  # GET /contact_imports/:id/download — the rows left out, with the reason (phone and e-mail masked).
  def download
    attachment = @campaign_import.error_csv
    return render_unprocessable('campaign_import.download_not_available') unless attachment.attached?

    send_data attachment.download, filename: attachment.blob.filename.to_s, type: 'text/csv', disposition: 'attachment'
  end

  private

  def ensure_contact_import_enabled
    render_error('contact_import.disabled', status: :not_found) unless ContactImports::Config.enabled?
  end

  def fetch_contact_import
    @campaign_import = Current.account.campaign_imports.contact_imports.includes(:user, :campaign_import_labels).find(params[:id])
  end

  def build_contact_import(file)
    Current.account.campaign_imports.create!(
      user: Current.user, status: :uploaded, mode: 'single_label', batch_count: 1,
      options: { default_country: 'BR', flow: CampaignImport::CONTACTS_FLOW, create_companies: params[:create_companies].to_s != 'false' },
      source_filename: file.original_filename, source_content_type: file.content_type, source_byte_size: file.size,
      source_format: File.extname(file.original_filename.to_s).delete('.').downcase
    )
  end

  def render_import(status: :ok)
    render 'api/v1/accounts/contact_imports/show', status: status
  end

  def render_unprocessable(code)
    render_error(code, status: :unprocessable_entity)
  end

  def render_error(code, status:)
    render json: { error: code }, status: status
  end
end
