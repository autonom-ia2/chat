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

  def whatsapp_payload(lead)
    verification = lead.metadata.to_h['whatsapp_verification'].to_h
    status = verification['status']
    phone = verification['phone'].presence || normalized_lead_phone(lead)

    {
      whatsapp_verification_status: status,
      whatsapp_verified: status == 'verified',
      whatsapp_phone: phone,
      whatsapp_url: whatsapp_url(status, phone)
    }
  end

  def advanced_filter_payload(lead)
    raw_payload = lead.raw_payload.to_h
    current_hours = raw_payload['currentOpeningHours'].to_h
    regular_hours = raw_payload['regularOpeningHours'].to_h

    {
      has_photos: Array(raw_payload['photos']).present?,
      open_now: current_hours.key?('openNow') ? current_hours['openNow'] : nil,
      opening_hours_summary: Array(current_hours['weekdayDescriptions']).presence ||
        Array(regular_hours['weekdayDescriptions']).presence
    }
  end

  def reviews_payload(lead)
    reviews = Array(
      lead.metadata.to_h['reviews_snapshot'].presence ||
        lead.raw_payload.to_h['reviews'].presence
    ).first(5)

    {
      reviews_snapshot: reviews
    }
  end

  def whatsapp_url(status, phone)
    return unless status == 'verified'

    digits = ::Autonomia::Prospecting::PhoneContract.parse(phone, region: phone_region)&.digits
    digits && "https://wa.me/#{digits}"
  end

  def normalized_lead_phone(lead)
    ::Autonomia::Prospecting::PhoneContract.e164(lead.phone, region: phone_region)
  end

  # País da busca da conta (settings.metadata['search_country']), lido uma vez por requisição.
  def phone_region
    @phone_region ||= ::Autonomia::Prospecting::PhoneContract.region_for(Current.account)
  end
end
