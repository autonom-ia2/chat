class Api::V1::Accounts::Autonomia::Prospecting::LeadsController < Api::V1::Accounts::Autonomia::Prospecting::BaseController
  def index
    render json: { payload: filtered_leads_scope.order(created_at: :desc).limit(100).map { |lead| lead_payload(lead) } }
  end

  def show
    render json: { payload: lead_payload(leads_scope.find(params[:id])) }
  end

  def update
    lead = leads_scope.find(params[:id])
    lead.update!(lead_params)

    render json: { payload: lead_payload(lead.reload) }
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def create_contact
    result = ::Autonomia::Prospecting::ContactConverter.new(
      lead: leads_scope.find(params[:id]),
      user: Current.user
    ).perform

    render json: {
      payload: {
        lead: lead_payload(result.lead),
        contact: contact_payload(result.contact),
        created: result.created
      }
    }, status: result.created ? :created : :ok
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  end

  def create_crm_card
    result = ::Autonomia::Prospecting::CrmCardConverter.new(
      lead: leads_scope.find(params[:id]),
      user: Current.user,
      pipeline_id: crm_card_params.require(:pipeline_id),
      stage_id: crm_card_params.require(:stage_id)
    ).perform

    render json: {
      payload: {
        lead: lead_payload(result.lead),
        crm_card: crm_card_payload(result.card),
        created: result.created
      }
    }, status: result.created ? :created : :ok
  rescue ActionController::ParameterMissing => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'crm.pipeline_or_stage_not_found' }, status: :not_found
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  rescue ::Autonomia::Prospecting::CrmCardConverter::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def verify_whatsapp
    result = ::Autonomia::Prospecting::WhatsappVerifier.new(
      lead: leads_scope.find(params[:id])
    ).perform

    render json: {
      payload: {
        lead: lead_payload(result.lead),
        exists: result.exists,
        phone: result.phone,
        chat_id: result.chat_id
      }
    }
  rescue ::Autonomia::Prospecting::WhatsappVerifier::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # Responde 202 na hora: site + IA rodam no EnrichLeadJob e o lead volta pelo evento prospecting.lead.updated (#678).
  def enrich
    lead = leads_scope.find(params[:id])
    return render json: { error: 'prospecting.enrichment.disabled' }, status: :unprocessable_entity unless research_enabled?

    unless ::Autonomia::Prospecting::LeadWorkQueue.enqueue_enrichment(lead)
      return render json: { error: I18n.t('autonomia.prospecting.errors.enrichment_in_progress') }, status: :conflict
    end

    render json: { payload: { lead: lead_payload(lead.reload) } }, status: :accepted
  end

  private

  def filtered_leads_scope
    scope = if params[:list_id].blank?
              leads_scope
            else
              lists_scope.find(params[:list_id]).leads
            end

    return scope if params[:status].blank?
    return scope.none unless ::Autonomia::Prospecting::Lead.statuses.key?(params[:status])

    scope.where(status: params[:status])
  end

  def lead_payload(lead)
    lead_payload_builder.build(lead)
  end

  def research_enabled?
    ::Autonomia::Prospecting::Config.research_enabled?(Current.account)
  end

  def contact_payload(contact)
    contact.as_json(only: [:id, :name, :email, :phone_number, :identifier])
  end

  def crm_card_payload(card)
    card.as_json(
      only: [:id, :title, :pipeline_id, :stage_id, :contact_id, :status, :source, :created_at, :updated_at]
    )
  end

  def crm_card_params
    params.require(:crm_card).permit(:pipeline_id, :stage_id)
  end

  def lead_params
    params.require(:lead).permit(:status, :discard_reason).tap do |attributes|
      attributes[:discard_reason] = nil unless attributes[:status] == 'discarded'
    end
  end
end
