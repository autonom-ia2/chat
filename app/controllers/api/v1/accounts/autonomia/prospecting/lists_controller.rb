class Api::V1::Accounts::Autonomia::Prospecting::ListsController < Api::V1::Accounts::Autonomia::Prospecting::BaseController
  include ::Autonomia::Prospecting::LeadExport

  # Baixar a planilha de leads é exportar: pede prospecting_manage, não só ver (#2147).
  before_action -> { check_permission_granted!('prospecting_manage') }, only: [:export]

  def index
    render json: { payload: lists_scope.order(created_at: :desc).limit(100).map { |list| list_payload(list) } }
  end

  def show
    list = lists_scope.find(params[:id])
    render json: { payload: list_payload(list, include_leads: true) }
  end

  def create
    list = lists_scope.create!(list_params.merge(user: Current.user))
    render json: { payload: list_payload(list) }, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  end

  # CSV ou Excel dos leads da lista (#682), na ordem em que a lista os mostra, com a nota do próprio lead.
  def export
    list = lists_scope.find(params[:id])
    leads = list.leads.includes(:company_profile, :contact).order(created_at: :desc).to_a
    send_leads_export(leads, scoring: {}, filename: "lista-#{list.id}")
  end

  def add_lead
    list = lists_scope.find(params[:id])
    lead = leads_scope.find(params.require(:lead_id))
    list_lead = list.list_leads.find_or_initialize_by(lead: lead)
    was_new = list_lead.new_record?
    list_lead.account = Current.account
    list_lead.save!
    lead.ready_for_campaign! unless lead.ready_for_campaign?

    render json: { payload: list_payload(list.reload, include_leads: true) }, status: was_new ? :created : :ok
  rescue ActionController::ParameterMissing
    render json: { error: I18n.t('autonomia.prospecting.errors.lead_required') }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  end

  def remove_lead
    list = lists_scope.find(params[:id])
    list.list_leads.where(prospect_lead_id: params[:lead_id]).destroy_all

    render json: { payload: list_payload(list.reload, include_leads: true) }
  end

  private

  def list_params
    params.require(:list).permit(:name, :description, metadata: {})
  end

  def list_payload(list, include_leads: false)
    payload = list_summary_payload(list)
    return payload unless include_leads

    payload.merge(
      leads: list.leads.includes(*lead_preloads).order(created_at: :desc).map { |lead| visible_lead_payload(lead_payload(lead)) }
    )
  end

  def lead_payload(lead)
    lead.as_json(only: ::Autonomia::Prospecting::LeadPayload::ATTRIBUTES).merge(
      source_label: lead.provider.to_s.humanize,
      contact_status: lead.contact_id.present? ? 'created' : 'pending',
      crm_status: lead.crm_card_id.present? ? 'created' : 'pending'
    ).merge(
      advanced_filter_payload(lead)
    ).merge(
      reviews_payload(lead)
    ).merge(
      whatsapp_payload(lead)
    ).merge(
      # O decisor da lista é o mesmo da busca: o da pesquisa (#679), nunca o nome que ficou gravado de antes.
      ::Autonomia::Prospecting::LeadPayload.new(account: Current.account).research(lead)
    ).merge(
      lead_payload_builder.crm_presence(lead)
    )
  end
end
