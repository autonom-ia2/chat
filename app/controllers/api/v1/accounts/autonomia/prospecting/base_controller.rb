class Api::V1::Accounts::Autonomia::Prospecting::BaseController < Api::V1::Accounts::BaseController
  before_action :ensure_feature_enabled
  before_action -> { check_module_permission!('prospecting') }

  private

  def ensure_feature_enabled
    render json: { error: 'autonomia.prospecting.disabled' }, status: :not_found unless ::Autonomia::Prospecting::Config.enabled?(Current.account)
  end

  def searches_scope
    ::Autonomia::Prospecting::Search.where(account: Current.account)
  end

  def leads_scope
    ::Autonomia::Prospecting::Lead.where(account: Current.account)
  end

  def lists_scope
    ::Autonomia::Prospecting::List.where(account: Current.account)
  end

  def setting
    ::Autonomia::Prospecting::Setting.for_account(Current.account)
  end

  # As partes do lead moram em LeadPayload, que o evento ao vivo também usa (#678).
  def whatsapp_payload(lead)
    lead_payload_builder.whatsapp(lead)
  end

  def advanced_filter_payload(lead)
    lead_payload_builder.advanced_filters(lead)
  end

  def reviews_payload(lead)
    lead_payload_builder.reviews(lead)
  end

  # A lista sem os leads: a mesma nas Listas e na campanha criada a partir da seleção da busca (#680).
  def list_summary_payload(list)
    list.as_json(
      only: [:id, :name, :description, :status, :metadata, :created_at, :updated_at]
    ).merge(
      lead_ids: list.leads.pluck(:id),
      leads_count: list.leads.count,
      campaign_segment: list.metadata.to_h['campaign_segment']
    )
  end

  # Um por requisição: o país da busca da conta é lido uma vez.
  def lead_payload_builder
    @lead_payload_builder ||= ::Autonomia::Prospecting::LeadPayload.new(account: Current.account)
  end
end
