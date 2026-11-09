class Api::V1::Accounts::Autonomia::Prospecting::BaseController < Api::V1::Accounts::BaseController
  before_action :ensure_feature_enabled
  before_action -> { check_module_permission!('prospecting') }
  # Dono escolhido sem o funil, de outra conta ou que não existe (#2694): o lote inteiro é recusado.
  rescue_from ::Autonomia::Prospecting::CrmCardOwner::NotAllowed, with: :render_crm_owner_not_allowed

  private

  # A tela mostra `error` como veio: a frase é sempre do I18n; o código de máquina, quando há, vai em `code` (#682).
  def ensure_feature_enabled
    return if ::Autonomia::Prospecting::Config.enabled?(Current.account)

    render json: { error: I18n.t('autonomia.prospecting.errors.disabled'), code: 'autonomia.prospecting.disabled' }, status: :not_found
  end

  # Enviar ao CRM cria card e roda a automação de entrada do estágio: exige a mesma permissão de criar card do próprio
  # CRM (Crm::CardPolicy#create?), além da prospecção (#680).
  def authorize_crm_card_create!
    return if Pundit.policy!(pundit_user, ::Crm::Card).create?

    render json: { error: I18n.t('autonomia.prospecting.crm_send.errors.forbidden'), code: 'prospecting.crm_send.forbidden' },
           status: :forbidden
  end

  # Com quem fica o card (#2694): escolher outra pessoa, e ver a lista de quem pode receber, só com a chave de funis
  # (CrmCardOwner.can_choose?), mais rígido que o CRM, por decisão do Rodrigo.
  def authorize_crm_owner_choice!
    return if ::Autonomia::Prospecting::CrmCardOwner.can_choose?(Current.account_user)

    render_crm_send_error('owner_forbidden', status: :forbidden)
  end

  # O `owner_id` do envio ao funil, sempre na raiz do pedido: no lote (leads/crm_cards) e também no envio individual
  # (leads/:id/crm_card), fora do envelope `crm_card`, para o contrato ser um só nos dois (o Guia lê `fora_do_envelope`).
  # Ausente, ou o de quem pede, é o fluxo de sempre (nil): o card fica com quem manda.
  def chosen_owner_id
    owner_id = params[:owner_id].presence&.to_s
    owner_id unless owner_id.nil? || owner_id == Current.user.id.to_s
  end

  def render_crm_owner_not_allowed
    render_crm_send_error(::Autonomia::Prospecting::CrmCardOwner::NotAllowed::CODE)
  end

  # Guardar empresas num Público de Campanhas (LeadAudiencesController, #2695) exige gerenciar campanhas.
  def campaign_manage?
    Current.account_user&.permission_granted?('campaign_manage') || false
  end

  # Os Públicos de Campanhas (LeadAudiencesController e AudiencesController, #2695 e #2775): sem
  # CAMPAIGN_JOURNEY_ENABLED e CAMPAIGN_IMPORT_ENABLED, 404 com a frase.
  def ensure_audiences_enabled
    return if ::CampaignJourney::Config.enabled? && ::CampaignImports::Config.enabled?

    render json: { error: I18n.t('autonomia.prospecting.audience.errors.disabled'), code: 'prospecting.audience.disabled' },
           status: :not_found
  end

  def authorize_campaign_manage!
    render_campaign_forbidden unless campaign_manage?
  end

  # Recusa de guardar ou acrescentar leads (AudienceFromLeads::Error): a frase do I18n em `error` (com o aviso de que os
  # contatos criados ficaram, quando a recusa veio depois deles), o código de máquina em `code` e quem ficou de fora.
  def render_audience_error(error)
    message = I18n.t("autonomia.prospecting.audience.errors.#{error.message}", max: ::Autonomia::Prospecting::AudienceFromLeads::MAX_LEADS)
    message = "#{message} #{I18n.t('autonomia.prospecting.audience.errors.contacts_saved')}" if error.contacts_saved
    render json: { error: message, code: "prospecting.audience.#{error.message}", left_out: error.left_out }, status: :unprocessable_entity
  end

  def render_campaign_forbidden
    render json: { error: I18n.t('autonomia.prospecting.campaign_errors.forbidden'), code: 'prospecting.campaign.forbidden' },
           status: :forbidden
  end

  # Recusa do envio ao CRM, na busca e no lead (#680, #682).
  def render_crm_send_error(code, status: :unprocessable_entity)
    render json: {
      error: I18n.t("autonomia.prospecting.crm_send.errors.#{code}", max: ::Autonomia::Prospecting::CrmCardBatch::MAX_LEADS),
      code: "prospecting.crm_send.#{code}"
    }, status: status
  end

  def searches_scope
    ::Autonomia::Prospecting::Search.where(account: Current.account)
  end

  # O agente só vê e mexe nos leads das próprias buscas e das listas da conta (#732, item 6). Vale para toda ação que
  # acha o lead pelo id, inclusive os lotes (descartar, contatos, CRM, campanha) e o "adicionar à lista": um lead posto
  # numa lista fica visível para a conta, então a lista não pode ser o atalho para o lead de outro agente.
  def leads_scope
    visibility.leads(::Autonomia::Prospecting::Lead.where(account: Current.account))
  end

  def lists_scope
    ::Autonomia::Prospecting::List.where(account: Current.account)
  end

  # Quem vê o quê (#732): o agente só as próprias buscas e os leads delas; o bloco técnico da nota só o administrador.
  def visibility
    @visibility ||= ::Autonomia::Prospecting::Visibility.new(Current.account_user)
  end

  def visible_searches_scope
    visibility.searches(searches_scope)
  end

  def visible_lead_payload(payload)
    visibility.lead_payload(payload)
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

  # A lista sem os leads (#680). campaign_segment é o segmento por etiqueta que a lista já tinha: a criação saiu (#2695),
  # o que ficou gravado continua aparecendo.
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

  # Associações que o payload do lead lê, carregadas de uma vez na lista (#732: o card do CRM, sem N+1).
  def lead_preloads
    ::Autonomia::Prospecting::LeadPayload::PRELOADS
  end
end
