# A tabela exportada (#682): as colunas do Orth (export do servidor e planilha do BuscaClient: empresa, decisor,
# confiança, WhatsApp verificado, Maps, coordenadas) mais o que só o chat2you tem (prioridade, faixa, sócios, status).
#
# Cada célula é o que a tela mostra do lead:
# - nota, prioridade e faixa são as da busca (lead_scoring), como no card; sem busca (lista), as do lead. Numa conta no
#   motor legado a nota do Orth fica em sombra na busca e não sai aqui; numa conta virada, sai a do Orth;
# - empresa, sócios e decisor vêm do bloco research (Research::Payload): só com a empresa confirmada;
# - CNPJ do cadastro vence o do site, como no Orth (company_cnpj ?? scraped_data.cnpj).
class Autonomia::Prospecting::Export::Table
  COLUMNS = %w[
    place_id name score priority band rating reviews_count category address neighborhood website phone whatsapp
    whatsapp_verified email instagram facebook linkedin cnpj legal_name trade_name registration_status registration_state
    decision_name decision_role decision_confidence decision_linkedin decision_instagram owners researched_at google_maps
    latitude longitude status source
  ].freeze
  CNPJ_LENGTH = 14

  # scoring: lead_scoring da busca (id do lead => nota, prioridade), ou vazio para uma lista.
  def initialize(account:, scoring: {})
    @payload = Autonomia::Prospecting::LeadPayload.new(account: account)
    @scoring = scoring.to_h
    @time_zone = ActiveSupport::TimeZone[Crm::Timezone::Resolver.new(account: account).name_or_default]
  end

  def rows(leads)
    [COLUMNS.map { |column| I18n.t("autonomia.prospecting.export.columns.#{column}") }, *leads.map { |lead| row(lead) }]
  end

  private

  def row(lead)
    values = place(lead).merge(scores(lead)).merge(contact(lead)).merge(research(lead))
    COLUMNS.map { |column| values[column] }
  end

  def place(lead)
    {
      'place_id' => lead.provider_place_id, 'name' => lead.name, 'rating' => decimal(lead.rating), 'reviews_count' => lead.reviews_count,
      'category' => lead.category, 'address' => address(lead), 'neighborhood' => lead.neighborhood,
      'google_maps' => @payload.advanced_filters(lead)[:google_maps_uri], 'latitude' => lead.latitude&.to_f,
      'longitude' => lead.longitude&.to_f, 'status' => I18n.t("autonomia.prospecting.export.statuses.#{lead.status}"),
      'source' => lead.provider.to_s.humanize
    }
  end

  # A mesma regra do searches_controller#search_scoring_payload: o que a busca guardou vence o que está no lead.
  def scores(lead)
    stored = @scoring[lead.id.to_s].to_h
    score = stored.key?('score') ? stored['score'] : lead.score
    priority = stored.key?('priority_score') ? stored['priority_score'] : lead.priority_score
    rounded_priority = priority&.to_f&.round
    band = Autonomia::Prospecting::Scoring::Band.code(rounded_priority)
    { 'score' => decimal(score), 'priority' => rounded_priority, 'band' => Autonomia::Prospecting::Scoring::Band.label(band) }
  end

  def contact(lead)
    whatsapp = @payload.whatsapp(lead)
    {
      'website' => lead.website, 'phone' => lead.phone, 'whatsapp' => whatsapp[:whatsapp_url],
      'whatsapp_verified' => whatsapp_verified(whatsapp[:whatsapp_verification_status]), 'email' => lead.enriched_email,
      'instagram' => lead.enriched_instagram, 'facebook' => lead.enriched_facebook, 'linkedin' => lead.enriched_linkedin
    }
  end

  def research(lead)
    research = Autonomia::Prospecting::Research::Payload.build(lead)
    company = research[:company].to_h
    company_values(lead, company).merge(decision_values(lead, research[:decision])).merge(
      'owners' => owners(research[:owners]),
      'researched_at' => research[:company] ? lead.research_completed_at&.in_time_zone(@time_zone)&.strftime('%d/%m/%Y %H:%M') : nil
    )
  end

  def company_values(lead, company)
    {
      'cnpj' => formatted_cnpj(company['cnpj'].presence || lead.enriched_cnpj), 'legal_name' => company['legal_name'],
      'trade_name' => company['trade_name'], 'registration_status' => company['registration_status'],
      'registration_state' => company['registration_state']
    }
  end

  def decision_values(lead, decision)
    return {} if decision.nil?

    {
      'decision_name' => decision[:name], 'decision_role' => decision[:role],
      'decision_confidence' => decision[:confidence] && "#{(decision[:confidence] * 100).round}%",
      'decision_linkedin' => lead.decision_linkedin, 'decision_instagram' => lead.decision_instagram
    }
  end

  def owners(list)
    names = Array(list).filter_map do |owner|
      owner = owner.to_h
      next if owner['name'].blank?

      owner['qualification'].present? ? "#{owner['name']} (#{owner['qualification']})" : owner['name']
    end
    names.join(' | ').presence
  end

  # Uma casa decimal; número redondo sai sem ela (64, não 64,0).
  def decimal(value)
    return if value.nil?

    rounded = value.to_f.round(1)
    (rounded % 1).zero? ? rounded.to_i : rounded
  end

  # Como formatLeadAddress da tela: endereço, e cidade com UF.
  def address(lead)
    [lead.address, [lead.city, lead.state].compact_blank.join(' ')].compact_blank.join(' - ').presence
  end

  def whatsapp_verified(status)
    return I18n.t('autonomia.prospecting.export.values.yes') if status == 'verified'

    I18n.t('autonomia.prospecting.export.values.no') if status == 'not_whatsapp'
  end

  # 00.000.000/0000-00, como a tela (formatCnpj). Com 14 dígitos, o Excel não o lê como número em notação científica.
  def formatted_cnpj(value)
    digits = Autonomia::Prospecting::Research::Cnpj.digits(value)
    return value.presence unless digits.length == CNPJ_LENGTH

    "#{digits[0, 2]}.#{digits[2, 3]}.#{digits[5, 3]}/#{digits[8, 4]}-#{digits[12, 2]}"
  end
end
