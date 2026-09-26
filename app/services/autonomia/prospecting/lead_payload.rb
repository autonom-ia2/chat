# O lead como a API devolve (GET leads/:id). Mora fora do controller porque o evento ao vivo
# (prospecting.lead.updated, #678) precisa mandar exatamente o mesmo objeto, de dentro de um job.
class Autonomia::Prospecting::LeadPayload
  ATTRIBUTES = [
    :id, :provider, :provider_place_id, :name, :phone, :website, :address, :city, :state, :country,
    :latitude, :longitude, :rating, :reviews_count, :category, :status, :discard_reason,
    :score, :priority_score, :priority_position, :search_rank, :score_breakdown, :negative_factors, :human_insight,
    :enrichment_status, :enrichment_requested_at, :enrichment_completed_at, :enrichment_source, :enrichment_error,
    :enriched_data, :decision_name, :decision_role, :decision_confidence, :decision_source_url, :decision_linkedin,
    :decision_instagram, :enriched_email, :enriched_whatsapp, :enriched_instagram, :enriched_linkedin,
    :enriched_facebook, :enriched_cnpj, :enrichment_summary,
    :consent_refused_at, :contact_id, :crm_card_id, :created_at, :updated_at
  ].freeze

  # O que o payload lê de outras tabelas. Quem monta a lista de leads carrega junto, para não fazer uma consulta por
  # lead (#732: o card do CRM, com funil, estágio e responsável).
  PRELOADS = [:company_profile, :contact, { crm_card: [:pipeline, :stage, :owner] }].freeze

  def initialize(account:)
    @account = account
  end

  def build(lead)
    lead.as_json(only: ATTRIBUTES).merge(
      source_label: lead.provider.to_s.humanize,
      contact_status: lead.contact_id.present? ? 'created' : 'pending',
      crm_status: lead.crm_card_id.present? ? 'created' : 'pending'
    ).merge(
      advanced_filters(lead)
    ).merge(
      reviews(lead)
    ).merge(
      whatsapp(lead)
    ).merge(
      research(lead)
    ).merge(
      crm_presence(lead)
    )
  end

  # Lead já no CRM (#732): funil, estágio e responsável do card que o lead tem. O lead continua da conta, sem bloqueio
  # por vendedor nem prazo; a tela usa isto para marcar o card e tirar o lead do envio em lote ao CRM.
  def crm_presence(lead)
    card = lead.crm_card
    return { crm_presence: nil } if card.nil?

    {
      crm_presence: {
        card_id: card.id, pipeline_id: card.pipeline_id, pipeline_name: card.pipeline&.name, stage_id: card.stage_id,
        stage_name: card.stage&.name, owner_id: card.owner_id, owner_name: card.owner&.name, status: card.status
      }
    }
  end

  # Pesquisa de empresa e decisor (#679), no formato do contrato com a tela. Vai junto o nome do contato real do lead
  # (#680): o selo "Contato atual" do sócio compara com ele, e não com o decisor, que pode não ser o contato.
  def research(lead)
    { research: Autonomia::Prospecting::Research::Payload.build(lead), contact_name: lead.contact&.name }
  end

  # O botão de WhatsApp usa o telefone do Google; se ele não é WhatsApp e o número achado no site foi
  # confirmado, usa o do site (#678).
  def whatsapp(lead)
    verification = whatsapp_verification(lead)
    status = verification['status']
    phone = verification['phone'].presence || normalized_lead_phone(lead)

    {
      whatsapp_verification_status: status,
      whatsapp_verified: status == 'verified',
      whatsapp_phone: phone,
      whatsapp_url: whatsapp_url(status, phone)
    }
  end

  def advanced_filters(lead)
    raw_payload = lead.raw_payload.to_h
    current_hours = raw_payload['currentOpeningHours'].to_h
    regular_hours = raw_payload['regularOpeningHours'].to_h

    {
      has_photos: Array(raw_payload['photos']).present?,
      open_now: current_hours.key?('openNow') ? current_hours['openNow'] : nil,
      opening_hours_summary: Array(current_hours['weekdayDescriptions']).presence ||
        Array(regular_hours['weekdayDescriptions']).presence,
      has_opening_hours: opening_hours_registered?(lead, regular_hours)
    }.merge(place_card(lead, raw_payload))
  end

  def reviews(lead)
    reviews = Array(
      lead.metadata.to_h['reviews_snapshot'].presence ||
        lead.raw_payload.to_h['reviews'].presence
    ).first(5)

    {
      reviews_snapshot: reviews
    }
  end

  private

  def whatsapp_verification(lead)
    google = lead.metadata.to_h['whatsapp_verification'].to_h
    site = lead.metadata.to_h['site_whatsapp_verification'].to_h
    return site if google['status'] != 'verified' && site['status'] == 'verified'

    google
  end

  # Bairro, fotos e link do Maps que o card mostra (#678). As colunas vêm do provider desde a E1; lead gravado antes
  # delas usa o que o Google devolveu no raw_payload.
  def place_card(lead, raw_payload)
    {
      neighborhood: lead.neighborhood,
      photo_count: lead.photo_count || Array(raw_payload['photos']).size,
      google_maps_uri: lead.google_maps_uri.presence || raw_payload['googleMapsUri']
    }
  end

  # Mesmo valor que o motor filtra (coluna gravada pelo provider, #677). Lead gravado antes da coluna usa a regra do
  # provider sobre o payload guardado: horário cadastrado é ter regularOpeningHours.
  def opening_hours_registered?(lead, regular_hours)
    lead.has_opening_hours.nil? ? regular_hours.present? : lead.has_opening_hours
  end

  def whatsapp_url(status, phone)
    return unless status == 'verified'

    digits = Autonomia::Prospecting::PhoneContract.parse(phone, region: phone_region)&.digits
    digits && "https://wa.me/#{digits}"
  end

  def normalized_lead_phone(lead)
    Autonomia::Prospecting::PhoneContract.e164(lead.phone, region: phone_region)
  end

  # País da busca da conta (settings.metadata['search_country']), lido uma vez por objeto.
  def phone_region
    @phone_region ||= Autonomia::Prospecting::PhoneContract.region_for(@account)
  end
end
