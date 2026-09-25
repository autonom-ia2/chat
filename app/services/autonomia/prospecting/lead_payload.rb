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
    :contact_id, :crm_card_id, :created_at, :updated_at
  ].freeze

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
    )
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
    }
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
