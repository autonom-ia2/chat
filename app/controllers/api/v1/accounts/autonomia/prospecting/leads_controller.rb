class Api::V1::Accounts::Autonomia::Prospecting::LeadsController < Api::V1::Accounts::Autonomia::Prospecting::BaseController
  before_action :authorize_crm_card_create!, only: [:create_crm_card, :create_crm_cards]
  before_action :authorize_crm_owner_choice!, only: [:create_crm_card, :create_crm_cards], if: :chosen_owner_id

  def index
    return render_queue if params[:view] == 'queue'

    leads = filtered_leads_scope.includes(*lead_preloads).order(created_at: :desc).limit(100)
    render json: { payload: leads.map { |lead| lead_payload(lead) } }
  end

  def show
    render json: { payload: lead_payload(leads_scope.find(params[:id])) }
  end

  def update
    lead = leads_scope.find(params[:id])
    # O status no_consent grava a recusa do lead, e ela entra nos contatos na mesma transação (chat#713). Nenhuma troca de
    # status a tira: descartar mantém a recusa; só o "Desfazer" (LeadConsentRefusalsController#destroy) a solta.
    ::Autonomia::Prospecting::ContactOptOutSync.new(account: Current.account).update_lead!(lead, lead_params)
    # Recusa ou descarte depois do segmento: no job da Prospecção a etiqueta sai, antes de a campanha ler o público por
    # ela, e o descartado sai dos pendentes da campanha em andamento.
    ::Autonomia::Prospecting::SegmentRefusalSync.enqueue(account: Current.account, leads: [lead]) if lead.saved_change_to_status?

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
  rescue ActionController::ParameterMissing
    render_crm_send_error('pipeline_not_found')
  rescue ::Autonomia::Prospecting::CrmCardConverter::Error
    render_crm_send_error('crm_disabled')
  rescue ActiveRecord::RecordNotFound
    render_crm_send_error('pipeline_not_found', status: :not_found)
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

  def verify_whatsapp
    result = ::Autonomia::Prospecting::WhatsappVerifier.new(
      lead: leads_scope.find(params[:id])
    ).perform

    render json: {
      payload: {
        # Apagado enquanto o WAHA respondia: o mesmo 404 do lead que já não existia.
        lead: lead_payload(result.lead || raise(ActiveRecord::RecordNotFound)),
        exists: result.exists,
        phone: result.phone,
        # pending: o telefone do lead mudou durante a consulta; nada vale para o número novo, que voltou à fila (ENRIQ-69).
        chat_id: result.chat_id, pending: result.pending == true
      }
    }
  rescue ::Autonomia::Prospecting::WhatsappVerifier::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # Responde 202 na hora: site + IA rodam no EnrichLeadJob e o lead volta pelo evento prospecting.lead.updated (#678).
  def enrich
    lead = leads_scope.find(params[:id])
    unless research_enabled?
      return render json: { error: I18n.t('autonomia.prospecting.errors.enrichment_disabled'), code: 'prospecting.enrichment.disabled' },
                    status: :unprocessable_entity
    end

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
    result = ::Autonomia::Prospecting::OwnerAdoption.new(
      lead: lead, user: Current.user, owner_name: params[:owner_name], can_update_card: can_update_lead_card?(lead)
    ).perform

    render json: { payload: lead_payload(lead.reload), contact_outcome: result.contact_outcome, shared_lead_name: result.shared_lead_name }
  rescue ::Autonomia::Prospecting::OwnerAdoption::NotAnOwner
    render json: { error: I18n.t('autonomia.prospecting.errors.owner_not_found'), code: 'prospecting.owner_not_found' },
           status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  end

  private

  # A fila "Para chamar" (#2697, view=queue): os leads que a pessoa vê e ainda não foram tratados, na ordem da chance
  # (ParaChamar), com o mesmo payload do index. A flag prospeccao_nova é só de rota e menu no painel; aqui valem o gate
  # da Prospecção (BaseController) e a visibilidade dos leads, como no resto do módulo.
  # Quem vê as buscas de todos recebe também quem fez a busca de onde o lead veio (found_by_name, "Achada por"); quem vê
  # só as próprias não recebe o nome de ninguém. meta.truncated diz que havia mais que o teto (ParaChamar::MAX_LEADS).
  def render_queue
    leads = ::Autonomia::Prospecting::ParaChamar.new(account: Current.account, user: Current.user).leads(leads_scope)
                                                .includes(*lead_preloads, search: :user).to_a
    shown = leads.first(::Autonomia::Prospecting::ParaChamar::MAX_LEADS)
    render json: { payload: shown.map { |lead| queue_lead_payload(lead) },
                   meta: { truncated: leads.size > shown.size } }
  end

  def queue_lead_payload(lead)
    payload = lead_payload(lead)
    visibility.all_searches? ? payload.merge(found_by_name: lead.search&.user&.name) : payload
  end

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

  # O bloco técnico da nota só vai para o administrador (#732, item 9).
  def lead_payload(lead) = visible_lead_payload(lead_payload_builder.build(lead))

  def research_enabled?
    ::Autonomia::Prospecting::Config.research_enabled?(Current.account)
  end

  def contact_payload(contact) = contact.as_json(only: [:id, :name, :email, :phone_number, :identifier])

  def crm_card_payload(card)
    card.as_json(
      only: [:id, :title, :pipeline_id, :stage_id, :contact_id, :status, :source, :created_at, :updated_at]
    )
  end

  # `owner_id` (#2694): com quem ficam os cards, conferido antes (authorize_crm_owner_choice!) e contra o funil (CrmCardBatch).
  def run_crm_send(lead_ids, pipeline_id, stage_id)
    ::Autonomia::Prospecting::CrmCardBatch.new(account: Current.account, user: Current.user, leads_scope: leads_scope, owner_id: chosen_owner_id,
                                               lead_ids: lead_ids, pipeline_id: pipeline_id, stage_id: stage_id).perform
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

  def crm_card_params
    params.require(:crm_card).permit(:pipeline_id, :stage_id)
  end

  def can_update_lead_card?(lead) = lead.crm_card.nil? || Pundit.policy!(pundit_user, lead.crm_card).update?

  def lead_params
    params.require(:lead).permit(:status, :discard_reason).tap do |attributes|
      attributes[:discard_reason] = nil unless attributes[:status] == 'discarded'
    end
  end
end
