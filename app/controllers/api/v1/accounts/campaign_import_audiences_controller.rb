# Públicos (#992): the column choice and the message-variable helpers of an audience import.
# Contract documented in docs/campaigns/publicos/api-992.md.
class Api::V1::Accounts::CampaignImportAudiencesController < Api::V1::Accounts::BaseController
  COLUMN_CHOICE_STATUSES = %w[needs_column_choice ready_to_confirm validation_failed].freeze

  before_action :ensure_campaign_import_enabled
  before_action :fetch_campaign_import
  before_action :check_authorization

  # PATCH /campaign_imports/:id/columns  { name:, phone:, email:, company: } (column index or null)
  def columns
    mapping = column_mapping
    return render_unprocessable('campaign_import.invalid_column_choice') unless mapping

    error_code = nil
    @campaign_import.with_lock do
      @campaign_import.reload
      unless COLUMN_CHOICE_STATUSES.include?(@campaign_import.status)
        error_code = 'campaign_import.column_choice_not_available'
        next
      end

      @campaign_import.update!(
        status: :validating, schema_resolution: @campaign_import.schema_resolution.to_h.merge('manual_mapping' => mapping)
      )
    end
    return render_unprocessable(error_code) if error_code

    CampaignImports::ValidateJob.perform_later(@campaign_import)
    render 'api/v1/accounts/campaign_imports/show'
  end

  # GET /campaign_imports/:id/variable_suggestions?variables[][key]=2&variables[][label]=mês de vencimento
  def variable_suggestions
    variables = params.permit(variables: [:key, :label]).fetch(:variables, []).map(&:to_h)
    suggestions = CampaignImports::VariableSuggester.new(@campaign_import, variables: variables).perform
    render json: { payload: suggestions }
  end

  # POST /campaign_imports/:id/variable_coverage  { mapping: { '2' => { source: 'extra', column: 'Vencimento' } }, defaults: {} }
  def variable_coverage
    result = CampaignImports::VariableCoverage.new(
      @campaign_import, mapping: hash_param(:mapping), defaults: hash_param(:defaults)
    ).perform
    render json: { payload: result.to_h }
  rescue CampaignImports::VariableCoverage::Error => e
    render_unprocessable("campaign_import.#{e.message}")
  end

  private

  def ensure_campaign_import_enabled
    render json: { error: 'campaign_import.disabled' }, status: :not_found unless CampaignImports::Config.enabled?
  end

  def fetch_campaign_import
    @campaign_import = Current.account.campaign_imports.includes(:user, :campaign_import_labels).find(params[:id])
    render_unprocessable('campaign_import.not_an_audience') unless @campaign_import.audience?
  end

  def check_authorization
    authorize(@campaign_import, :"#{action_name}?")
  end

  # Indices are checked against the columns the reader stored; at least a phone or an email column.
  def column_mapping
    column_count = Array(@campaign_import.schema_resolution.to_h['columns']).size
    CampaignImports::ColumnChoice.new(params.permit(*CampaignImports::ColumnChoice::TARGETS), column_count: column_count).mapping
  end

  # Free-form maps keyed by template variable; the services check every key and value.
  def hash_param(key)
    value = params[key]
    value.respond_to?(:permit!) ? value.permit!.to_h : {}
  end

  def render_unprocessable(code)
    render json: { error: code }, status: :unprocessable_entity
  end
end
