# Empresa do Chatwoot (companies) a partir do lead da prospecção (#680, frente A).
#
# - Reaproveita a empresa da conta pelo CNPJ (additional_attributes['cnpj'], 14 dígitos): o do cadastro que a pesquisa
#   achou (E3) e, sem ele, o que o site mostrou, só com o dígito verificador fechando. Sem CNPJ, pelo domínio do site.
# - Domínio é o host do site sem www, e só quando o site é a raiz do domínio. Site com caminho (ou com query que não
#   seja utm) é página dentro de uma plataforma (doctoralia.com.br/clinica/x, cardápio, agendamento): o host é da
#   plataforma, não da empresa. Site em rede social, WhatsApp ou encurtador também não tem domínio da empresa: dois
#   negócios no Instagram não são a mesma empresa. Mesmo domínio com outro CNPJ (filial, franquia) é
#   outra empresa, criada sem domínio, porque o domínio é único por conta.
# - Empresa existente só ganha o que está vazio: nunca sobrescreve o que o usuário escreveu, nem o nome, nem a origem.
# - Concorrência: dois leads da mesma empresa ao mesmo tempo esbarram no índice único (conta e CNPJ, conta e domínio);
#   quem perde cai no RecordNotUnique e procura de novo. Cada escrita vai num savepoint, para o retry funcionar dentro
#   da transação de quem chama.
class Autonomia::Prospecting::CompanyUpserter
  Result = Struct.new(:company, :created, keyword_init: true)

  SOURCE = 'autonomia_prospecting'.freeze
  WWW = 'www.'.freeze
  ROOT_PATHS = ['', '/'].freeze
  TRACKING_PARAM_PREFIX = 'utm_'.freeze
  MAX_ATTEMPTS = 3
  COMPANY_KEY = 'chatwoot_company_id'.freeze
  # Host em que o caminho, e não o domínio, identifica o negócio. Comparado pelo domínio registrável.
  SHARED_HOSTS = %w[
    instagram.com facebook.com fb.com fb.me wa.me whatsapp.com linktr.ee linkedin.com google.com goo.gl youtube.com
    tiktok.com twitter.com x.com t.me bit.ly ifood.com.br
  ].to_set.freeze
  DOMAIN_CHARS = (('a'..'z').to_a + ('0'..'9').to_a + %w[- .]).to_set.freeze

  def initialize(lead:)
    @lead = lead
    @account = lead.account
  end

  def perform
    attempts = 0
    begin
      attempts += 1
      upsert
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
      raise if attempts >= MAX_ATTEMPTS || !lost_race?(e)

      retry
    end
  end

  private

  # O índice pega a corrida no INSERT; a validação de domínio único do Company pega quando a outra já gravou.
  def lost_race?(error)
    error.is_a?(ActiveRecord::RecordNotUnique) || error.record.errors.of_kind?(:domain, :taken)
  end

  def upsert
    company = find_existing
    result = company ? Result.new(company: fill_blanks!(company), created: false) : Result.new(company: create!, created: true)
    remember!(result.company)
    result
  end

  # Sem CNPJ e sem domínio, a empresa do lead é a que ele já usou (gravada no lead) ou a que está no contato dele: criar
  # contato e depois enviar ao CRM, ou trocar o decisor, não pode deixar uma empresa nova a cada passo. Contato que é de
  # outro lead (mesmo telefone ou e-mail) traz a empresa daquele lead, não a deste.
  def find_existing
    by_cnpj || by_domain || remembered_company || linked_company
  end

  def remembered_company
    company_id = @lead.metadata.to_h[COMPANY_KEY]
    companies.find_by(id: company_id) if company_id.present?
  end

  def remember!(company)
    return if @lead.metadata.to_h[COMPANY_KEY] == company.id

    @lead.update!(metadata: @lead.metadata.to_h.merge(COMPANY_KEY => company.id))
  end

  def linked_company
    contact = @lead.contact
    owner_id = Autonomia::Prospecting::ContactConverter.owner_lead_id(contact)
    return if owner_id.present? && owner_id != @lead.id

    company = contact&.company
    company if company&.account_id == @account.id
  end

  def by_cnpj
    return if cnpj.nil?

    companies.find_by("additional_attributes ->> 'cnpj' = ?", cnpj)
  end

  # Empresa do mesmo domínio com outro CNPJ é outra empresa.
  def by_domain
    return if domain.nil?

    company = companies.find_by(domain: domain)
    return company if company.nil? || cnpj.nil?

    existing_cnpj = company.additional_attributes.to_h['cnpj']
    existing_cnpj.blank? || existing_cnpj == cnpj ? company : nil
  end

  # Sem CNPJ o domínio é a identidade: se outra empresa o tem, a corrida foi perdida e a procura de novo a acha.
  def create!
    company = companies.new(name: company_name, domain: cnpj ? free_domain : domain, additional_attributes: new_attributes)
    in_savepoint { company.save! }
    company
  end

  def fill_blanks!(company)
    current = company.additional_attributes.to_h
    missing = new_attributes.except('source').reject { |key, _value| current[key].present? }
    company.additional_attributes = current.merge(missing)
    company.domain = free_domain(except: company) if company.domain.blank?
    in_savepoint { company.save! } if company.changed?
    company
  end

  def in_savepoint(&)
    Company.transaction(requires_new: true, &)
  end

  def free_domain(except: nil)
    return if domain.nil?

    taken = companies.where(domain: domain)
    taken = taken.where.not(id: except.id) if except
    taken.exists? ? nil : domain
  end

  def companies
    @account.companies
  end

  def new_attributes
    @new_attributes ||= {
      'cnpj' => cnpj,
      'legal_name' => research_company['legal_name'],
      'trade_name' => research_company['trade_name'],
      'registration_status' => research_company['registration_status'],
      'registration_state' => research_company['registration_state'],
      'address' => @lead.address,
      'phone' => phone,
      'instagram' => @lead.enriched_instagram,
      'linkedin' => @lead.enriched_linkedin,
      'facebook' => @lead.enriched_facebook,
      'source' => SOURCE
    }.transform_values(&:presence).compact
  end

  def company_name
    [research_company['trade_name'], research_company['legal_name'], @lead.name]
      .find(&:present?).to_s.first(Limits::COMPANY_NAME_LENGTH_LIMIT)
  end

  # Empresa da pesquisa só quando ela foi achada, no retrato gravado no lead (o mesmo que a tela mostra).
  def research_company
    @research_company ||= Autonomia::Prospecting::Research::Payload.build(@lead)[:company].to_h.stringify_keys
  end

  def cnpj
    return @cnpj if defined?(@cnpj)

    researched = Autonomia::Prospecting::Research::Normalization.digits(research_company['cnpj'])
    @cnpj = if researched.length == Autonomia::Prospecting::Research::Cnpj::LENGTH
              researched
            else
              Autonomia::Prospecting::Research::Cnpj.normalize(@lead.enriched_cnpj)
            end
  end

  def domain
    return @domain if defined?(@domain)

    @domain = site_domain
  end

  def site_domain
    host = site_host
    return if host.nil? || host.exclude?('.') || !host.each_char.all? { |char| DOMAIN_CHARS.include?(char) }
    return if SHARED_HOSTS.include?(PublicSuffix.domain(host))

    host
  rescue PublicSuffix::Error
    nil
  end

  def site_host
    raw = @lead.website.to_s.strip
    return if raw.empty?

    uri = URI.parse(raw.include?('://') ? raw : "https://#{raw}")
    return unless site_root?(uri)

    uri.host.to_s.downcase.delete_prefix(WWW).presence
  rescue URI::InvalidURIError, ArgumentError
    nil
  end

  def site_root?(uri)
    ROOT_PATHS.include?(uri.path.to_s) && tracking_only_query?(uri.query)
  end

  def tracking_only_query?(query)
    return true if query.blank?

    URI.decode_www_form(query).all? { |key, _value| key.downcase.start_with?(TRACKING_PARAM_PREFIX) }
  end

  def phone
    Autonomia::Prospecting::PhoneContract.e164(@lead.phone, region: Autonomia::Prospecting::PhoneContract.region_for(@account))
  end
end
