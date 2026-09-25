# Contato do Chatwoot a partir do lead da prospecção (#680, frente A).
#
# - O contato fica vinculado à empresa do lead (CompanyUpserter), a não ser que já tenha outra empresa.
# - Com decisor (pesquisa confirmada ou possível, ou o decisor que a IA achou antes de existir pesquisa), o contato é a
#   pessoa: nome do decisor, cargo, empresa, e-mail, o WhatsApp verificado e as redes. Sem decisor, é a própria empresa.
# - Acha o contato existente pelo telefone, pelo identificador da prospecção ou pelo e-mail; reenvio nunca duplica.
# - Contato existente só ganha o que está vazio. O nome só muda quando fomos nós que o escrevemos (o nome gravado em
#   custom_attributes, o do lead ou o da empresa): assim "Usar como contato" troca a empresa pela pessoa, mas o nome que
#   o usuário deu fica.
class Autonomia::Prospecting::ContactConverter
  Result = Struct.new(:lead, :contact, :created, :company, keyword_init: true)

  DECISION_STATUSES = %w[confirmed possible].freeze
  WRITTEN_NAME_KEY = 'autonomia_prospecting_contact_name'.freeze

  def initialize(lead:, user:, company: nil)
    @lead = lead
    @account = lead.account
    @user = user
    @company = company
  end

  def perform
    created = false
    contact = nil

    ActiveRecord::Base.transaction do
      @lead.lock!
      @company ||= Autonomia::Prospecting::CompanyUpserter.new(lead: @lead).perform.company
      contact = @lead.contact || find_existing_contact || build_contact
      created = contact.new_record?
      enrich_contact(contact)
      contact.save!
      @lead.update!(contact: contact) if @lead.contact_id != contact.id
    end

    Result.new(lead: @lead.reload, contact: contact.reload, created: created, company: @company)
  end

  private

  def find_existing_contact
    by_phone || by_identifier || by_email
  end

  def by_phone
    phones = [contact_phone, normalized_phone].compact.uniq
    return if phones.empty?

    @account.contacts.find_by(phone_number: phones)
  end

  def by_identifier
    @account.contacts.find_by(identifier: prospecting_identifier)
  end

  def by_email
    return if email.nil?

    @account.contacts.from_email(email)
  end

  def build_contact
    @account.contacts.new(contact_type: :lead, identifier: prospecting_identifier)
  end

  def enrich_contact(contact)
    rename(contact) if replaceable_name?(contact)
    fill_unique(contact, :phone_number, contact_phone)
    fill_unique(contact, :email, email)
    fill_unique(contact, :identifier, prospecting_identifier)
    contact.company = @company if contact.company_id.nil?
    contact.location = contact.location.presence || location
    contact.additional_attributes = merged_additional_attributes(contact)
    contact.custom_attributes = contact.custom_attributes.to_h.merge(custom_attributes).compact
  end

  def rename(contact)
    contact.name = contact_name
    contact.additional_attributes = contact.additional_attributes.to_h.merge('job_title' => decision_maker? ? @lead.decision_role : nil).compact
    contact.custom_attributes = contact.custom_attributes.to_h.merge(WRITTEN_NAME_KEY => contact_name)
  end

  def replaceable_name?(contact)
    return true if contact.new_record? || contact.name.blank?

    [contact.custom_attributes.to_h[WRITTEN_NAME_KEY], @lead.name, @company.name].compact.include?(contact.name)
  end

  # Valor único por conta (telefone, e-mail, identificador): só preenche o vazio, e só se outro contato não o usa.
  def fill_unique(contact, attribute, value)
    return if value.blank? || contact.public_send(attribute).present?

    scope = @account.contacts.where(attribute => value)
    scope = scope.where.not(id: contact.id) if contact.persisted?
    contact.public_send("#{attribute}=", value) unless scope.exists?
  end

  def merged_additional_attributes(contact)
    current = contact.additional_attributes.to_h
    missing = additional_attributes.reject { |key, _value| current[key].present? }
    social = current['social_profiles'].to_h
    missing_social = social_profiles.reject { |key, _value| social[key].present? }
    current.merge(missing).merge('social_profiles' => social.merge(missing_social)).compact_blank
  end

  def decision_maker?
    return false if @lead.decision_name.blank?

    DECISION_STATUSES.include?(@lead.decision_research_status) ||
      @lead.decision_research_status == Autonomia::Prospecting::Research::States::NOT_RESEARCHED
  end

  def contact_name
    decision_maker? ? @lead.decision_name : @company.name
  end

  # O WhatsApp confirmado vale mais que o telefone do Google (mesma regra do botão de WhatsApp do card).
  def contact_phone
    @contact_phone ||= begin
      whatsapp = Autonomia::Prospecting::LeadPayload.new(account: @account).whatsapp(@lead)
      whatsapp[:whatsapp_verified] ? whatsapp[:whatsapp_phone] : normalized_phone
    end
  end

  def normalized_phone
    @normalized_phone ||= Autonomia::Prospecting::PhoneContract.e164(@lead.phone, region: Autonomia::Prospecting::PhoneContract.region_for(@account))
  end

  # Mesma validação do modelo Contact: e-mail que ele recusaria não entra.
  def email
    return @email if defined?(@email)

    candidate = @lead.enriched_email.to_s.strip.downcase
    @email = candidate.present? && Devise.email_regexp.match?(candidate) ? candidate : nil
  end

  def prospecting_identifier
    @prospecting_identifier ||= [
      'prospecting',
      @lead.provider,
      @lead.provider_place_id.presence || @lead.dedupe_key
    ].join(':')
  end

  def location
    [@lead.address, @lead.city, @lead.state, @lead.country].compact_blank.join(', ')
  end

  def additional_attributes
    {
      'company_name' => @company.name,
      'city' => @lead.city,
      'state' => @lead.state,
      'country' => @lead.country,
      'description' => @lead.category,
      'website' => @lead.website,
      'source' => 'autonomia_prospecting'
    }.compact_blank
  end

  # Redes no formato do Chatwoot: o caminho depois do domínio (o painel monta o link com o domínio da rede).
  def social_profiles
    person = decision_maker?
    urls = {
      'instagram' => (person && @lead.decision_instagram.presence) || @lead.enriched_instagram,
      'linkedin' => (person && @lead.decision_linkedin.presence) || @lead.enriched_linkedin,
      'facebook' => @lead.enriched_facebook
    }
    urls.transform_values { |url| profile_handle(url) }.compact_blank
  end

  def profile_handle(url)
    return if url.blank?

    URI.parse(url.strip).path.to_s.delete_prefix('/').delete_suffix('/').presence
  rescue URI::InvalidURIError
    nil
  end

  def custom_attributes
    {
      'autonomia_prospecting_lead_id' => @lead.id,
      'autonomia_prospecting_provider' => @lead.provider,
      'autonomia_prospecting_provider_place_id' => @lead.provider_place_id,
      'autonomia_prospecting_rating' => @lead.rating&.to_f,
      'autonomia_prospecting_reviews_count' => @lead.reviews_count,
      'autonomia_prospecting_converted_by_id' => @user&.id
    }
  end
end
