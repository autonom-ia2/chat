# Públicos (#992): the column choice and the message-variable helpers of an audience import.
# Contract documented in docs/campaigns/publicos/api-992.md.
class Api::V1::Accounts::CampaignImportAudiencesController < Api::V1::Accounts::BaseController
  COLUMN_CHOICE_STATUSES = %w[needs_column_choice ready_to_confirm validation_failed].freeze
  COMPANIES_CHOICE_STATUSES = %w[uploaded validating needs_column_choice ready_to_confirm validation_failed].freeze
  BOOLEAN_VALUES = %w[true false].freeze
  CHANNELS = %w[email whatsapp].freeze
  PROBLEM_ROWS_PER_PAGE = 50
  CONTACTS_PER_PAGE = 25
  SAMPLE_ROW_STATUSES = %i[valid imported].freeze

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

  # PATCH /campaign_imports/:id/companies  { create_companies: true | false } (#998 "Criar e ligar")
  # Only before saving: the importer reads the switch once the audience is queued.
  def companies
    value = params.permit(:create_companies)[:create_companies].to_s
    return render_unprocessable('campaign_import.invalid_companies_choice') unless BOOLEAN_VALUES.include?(value)

    error_code = nil
    @campaign_import.with_lock do
      @campaign_import.reload
      unless COMPANIES_CHOICE_STATUSES.include?(@campaign_import.status)
        error_code = 'campaign_import.companies_choice_not_available'
        next
      end

      @campaign_import.update!(options: @campaign_import.options.to_h.merge('create_companies' => value == 'true'))
    end
    return render_unprocessable(error_code) if error_code

    render 'api/v1/accounts/campaign_imports/show'
  end

  # PATCH /campaign_imports/:id/channels  { email: true | false, whatsapp: true | false } (#1005, J5/J6)
  # Turning a channel off takes the audience out of that channel; a channel without data cannot be turned on,
  # and a channel cannot be turned off while a scheduled or running campaign sends to the audience through it.
  def channels
    choice = channels_choice
    return render_unprocessable('campaign_import.invalid_channels_choice') unless choice

    error_code = nil
    in_use = []
    @campaign_import.with_lock do
      @campaign_import.reload
      current = @campaign_import.channels.to_h
      if turning_on_without_data?(current, choice)
        error_code = 'campaign_import.channel_without_data'
        next
      end
      in_use = campaigns_using_channels_turned_off(choice)
      next if in_use.any?

      @campaign_import.update!(channels: channels_with(current, choice))
    end
    return render json: CampaignImports::AudienceUsage.error_payload(in_use), status: :unprocessable_entity if in_use.any?
    return render_unprocessable(error_code) if error_code

    render 'api/v1/accounts/campaign_imports/show'
  end

  # GET /campaign_imports/:id/problem_rows?page=1 (#993, B5): rows left out, reason per row, contact masked, no name.
  def problem_rows
    page = [params[:page].to_i, 1].max
    scope = @campaign_import.campaign_import_rows.status_invalid.order(:row_number)
    rows = scope.offset((page - 1) * PROBLEM_ROWS_PER_PAGE).limit(PROBLEM_ROWS_PER_PAGE)
    render json: {
      payload: rows.map { |row| problem_row(row) },
      meta: { count: scope.count, page: page, per_page: PROBLEM_ROWS_PER_PAGE }
    }
  end

  # GET /campaign_imports/:id/contacts?page=1 (#993, side panel "Ver contatos e empresas"): the contacts
  # saved by this audience, paged, with their company. Contacts has no list filter, so the panel reads them here.
  def contacts
    page = [params[:page].to_i, 1].max
    ids = @campaign_import.campaign_import_rows.status_imported.where.not(contact_id: nil).distinct.pluck(:contact_id)
    scope = Current.account.contacts.where(id: ids).order(:name, :id)
    records = scope.offset((page - 1) * CONTACTS_PER_PAGE).limit(CONTACTS_PER_PAGE)
    records = records.includes(:company) if Contact.reflect_on_association(:company)
    render json: {
      payload: records.map { |contact| contact_payload(contact) },
      meta: { count: scope.count, page: page, per_page: CONTACTS_PER_PAGE }
    }
  end

  # GET /campaign_imports/:id/sample_contact (#993, PRD §6.3 "Como o cliente vê"): the first eligible row of
  # this audience, only its own values. `payload: null` when the audience has none.
  def sample_contact
    row = @campaign_import.campaign_import_rows.where(status: SAMPLE_ROW_STATUSES).order(:row_number).first
    render json: { payload: row && sample_payload(row) }
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
    # Old imports (Base Campanha) also list their contacts in the side panel (F1).
    return if @campaign_import.audience? || action_name == 'contacts'

    render_unprocessable('campaign_import.not_an_audience')
  end

  def check_authorization
    authorize(@campaign_import, :"#{action_name}?")
  end

  # Indices are checked against the columns the reader stored; at least a phone or an email column.
  def column_mapping
    column_count = Array(@campaign_import.schema_resolution.to_h['columns']).size
    CampaignImports::ColumnChoice.new(params.permit(*CampaignImports::ColumnChoice::TARGETS), column_count: column_count).mapping
  end

  # { "email" => true, "whatsapp" => false } with only known channels and true/false values; nil otherwise.
  def channels_choice
    choice = params.permit(*CHANNELS).to_h
    return if choice.empty? || choice.values.any? { |value| BOOLEAN_VALUES.exclude?(value.to_s) }

    choice.transform_values { |value| value.to_s == 'true' }
  end

  def turning_on_without_data?(current, choice)
    choice.any? { |channel, enabled| enabled && current.dig(channel, 'count').to_i.zero? }
  end

  def campaigns_using_channels_turned_off(choice)
    usage = CampaignImports::AudienceUsage.new(@campaign_import)
    choice.reject { |_channel, enabled| enabled }.keys.flat_map { |channel| usage.pending_campaigns(channel: channel) }.uniq
  end

  def channels_with(current, choice)
    current.merge(choice.to_h { |channel, enabled| [channel, current[channel].to_h.merge('enabled' => enabled)] })
  end

  def problem_row(row)
    contact = row.raw_phone_masked.presence || row.email_masked.presence
    { row_number: row.row_number, contact_masked: contact, errors: Array(row.error_messages) }
  end

  def contact_payload(contact)
    { id: contact.id, name: contact.name, email: contact.email, phone_number: contact.phone_number,
      company_name: contact.try(:company)&.name.presence || contact.additional_attributes.to_h['company_name'] }
  end

  def sample_payload(row)
    name = (row.contact&.name.presence || row.normalized_name.presence || row.raw_name).to_s.squish
    {
      name: name, first_name: name.split.first.to_s,
      company_name: row.contact.try(:company)&.name.presence || row.company_name,
      extra_values: row.extra_values.to_h
    }
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
