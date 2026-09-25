class Api::V1::Accounts::Autonomia::Prospecting::LeadsController < Api::V1::Accounts::Autonomia::Prospecting::BaseController
  before_action :authorize_crm_card_create!, only: [:create_crm_card, :create_crm_cards]
  before_action -> { authorize_campaign_update!(params[:campaign_id]) }, only: [:create_campaign_segment]

  def index
    leads = filtered_leads_scope.includes(:company_profile, :contact).order(created_at: :desc).limit(100)
    render json: { payload: leads.map { |lead| lead_payload(lead) } }
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

  # Envio individual: o mesmo caminho do lote, com o mesmo resultado por lead (#680). Leva também o lead e o card, que
  # a tela já lia. `created` agora é a lista do lote, não mais true/false.
  def create_crm_card
    lead = leads_scope.find(params[:id])
    result = run_crm_send([lead.id], crm_card_params.require(:pipeline_id), crm_card_params.require(:stage_id))
    payload = crm_send_payload(result).merge(single_lead_payload(lead.reload))
    return render json: { payload: payload }, status: result.created.any? ? :created : :ok if result.failed.empty?

    render_single_failure(result.failed.first, payload)
  rescue ActionController::ParameterMissing, ::Autonomia::Prospecting::CrmCardConverter::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'crm.pipeline_or_stage_not_found' }, status: :not_found
  end

  # Envio ao CRM em lote (#680): até 30 leads, cada um na própria transação.
  def create_crm_cards
    result = run_crm_send(params.require(:lead_ids), params.require(:pipeline_id), params.require(:stage_id))
    render json: { payload: crm_send_payload(result) }
  rescue ActionController::ParameterMissing => e
    render_crm_send_error(e.param.to_s == 'lead_ids' ? 'no_leads' : 'pipeline_not_found')
  rescue ::Autonomia::Prospecting::CrmCardBatch::NoLeads
    render_crm_send_error('no_leads')
  rescue ::Autonomia::Prospecting::CrmCardBatch::TooManyLeads
    render_crm_send_error('too_many_leads')
  rescue ActiveRecord::RecordNotFound
    render_crm_send_error('pipeline_not_found', status: :not_found)
  rescue ::Autonomia::Prospecting::CrmCardConverter::Error
    render_crm_send_error('crm_disabled')
  end

  # "Adicionar à campanha" a partir da seleção (#680, ACAO-25/26/27): a seleção vira lista e segue o segmento das Listas.
  def create_campaign_segment
    result = ::Autonomia::Prospecting::SelectionCampaignSegment.new(
      account: Current.account, user: Current.user, lead_ids: params[:lead_ids],
      campaign_id: params[:campaign_id], segment_name: params[:segment_name]
    ).perform
    render json: { payload: selection_segment_payload(result) }, status: :created
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'prospecting.campaign.not_found' }, status: :not_found
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  rescue ::Autonomia::Prospecting::SelectionCampaignSegment::Error => e
    segment = ::Autonomia::Prospecting::CampaignSegmentPayload.blocked_only(e.blocked_leads, missing_lead_ids: e.missing_lead_ids)
    render json: { error: e.message, payload: { segment: segment } }, status: :unprocessable_entity
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

  # Pesquisa de empresa e decisor (#679): 202 na hora, a pesquisa roda no ResearchJob e o lead volta pelo evento.
  # `force` é o "verificar novamente": ignora o reaproveitamento. Pedido com o lead já na fila devolve o mesmo pedido.
  def research
    lead = leads_scope.find(params[:id])
    unless research_enabled?
      return render json: { error: I18n.t('autonomia.prospecting.errors.research_disabled'), code: 'prospecting.research.disabled' },
                    status: :unprocessable_entity
    end

    ::Autonomia::Prospecting::Research::Queue.enqueue(lead, force: ActiveModel::Type::Boolean.new.cast(params[:force]) || false)
    render json: { payload: { lead: lead_payload(lead.reload) } }, status: :accepted
  end

  # "Usar como contato" (#680): um sócio da pesquisa vira o decisor e o contato do lead. Responde o lead, e ao lado dele
  # o que aconteceu com o contato (contact_outcome), para a tela não dizer que trocou o contato quando não trocou.
  def adopt_owner
    lead = leads_scope.find(params[:id])
    result = ::Autonomia::Prospecting::OwnerAdoption.new(lead: lead, user: Current.user, owner_name: params[:owner_name]).perform

    render json: { payload: lead_payload(lead.reload), contact_outcome: result.contact_outcome, shared_lead_name: result.shared_lead_name }
  rescue ::Autonomia::Prospecting::OwnerAdoption::NotAnOwner
    render json: { error: I18n.t('autonomia.prospecting.errors.owner_not_found'), code: 'prospecting.owner_not_found' },
           status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
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

  def run_crm_send(lead_ids, pipeline_id, stage_id)
    ::Autonomia::Prospecting::CrmCardBatch.new(
      account: Current.account, user: Current.user, lead_ids: lead_ids, pipeline_id: pipeline_id, stage_id: stage_id
    ).perform
  end

  def crm_send_payload(result)
    { created: result.created, existing: result.existing, failed: result.failed }
  end

  def single_lead_payload(lead)
    { lead: lead_payload(lead), crm_card: lead.crm_card && crm_card_payload(lead.crm_card) }
  end

  def render_single_failure(failure, payload)
    render json: { error: failure[:message], code: failure[:reason_code], payload: payload }, status: :unprocessable_entity
  end

  def selection_segment_payload(result)
    {
      list: list_summary_payload(result.segment.list),
      segment: ::Autonomia::Prospecting::CampaignSegmentPayload.build(result.segment, missing_lead_ids: result.missing_lead_ids)
    }
  end

  # A tela mostra `error` como veio: o texto é sempre do I18n; `code` é para quem trata o caso.
  def render_crm_send_error(code, status: :unprocessable_entity)
    render json: {
      error: I18n.t("autonomia.prospecting.crm_send.errors.#{code}", max: ::Autonomia::Prospecting::CrmCardBatch::MAX_LEADS),
      code: "prospecting.crm_send.#{code}"
    }, status: status
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
