# Leitura comum aos quatro parsers de cadastro (porte de registry/parser-utils.ts do Orth). Cada parser só diz onde
# cada campo mora no corpo da sua fonte; a normalização e a validação semântica são estas, iguais para todos.
module Autonomia::Prospecting::Research::Registry::ParserSupport
  Normalization = Autonomia::Prospecting::Research::Normalization
  Registry = Autonomia::Prospecting::Research::Registry

  UFS = %w[AC AL AP AM BA CE DF ES GO MA MT MS MG PA PB PR PE PI RJ RN RS RO RR SC SP SE TO].to_set.freeze
  ADULT_AGE = 18
  CNPJ_LENGTH = 14
  LEGAL_NATURE_CODE_LENGTH = 4
  CNAE_LENGTH = 7
  DATE_LENGTH = 10
  QSA_FAILURES = { 'missing' => 'qsa_missing', 'malformed' => 'qsa_malformed' }.freeze
  # Código da faixa etária da Receita (BrasilAPI e OpenCNPJ): 1 = 0 a 12 anos, 2 = 13 a 20 anos.
  MINOR_AGE_CODES = Set[1, 2].freeze
  # Qualificação do representante legal que só existe para quem não responde sozinho pelos próprios atos (menor ou
  # incapaz), comparada pela chave da Receita (Normalization.key). Procurador e administrador não entram.
  INCAPABLE_REPRESENTATIVES = Set['MAE', 'PAI', 'TUTOR', 'TUTORA', 'CURADOR', 'CURADORA', 'ASSISTENTE'].freeze

  module_function

  def record(value) = value.is_a?(Hash) ? value : nil

  def text(value) = Normalization.squish(value)

  def nested(value, key) = record(value)&.[](key)

  def cnpj(value)
    return nil unless value.is_a?(String) || value.is_a?(Integer)

    digits = Normalization.digits(value)
    digits.length == CNPJ_LENGTH ? digits : nil
  end

  # Situação cadastral da Receita, sem acento e em maiúsculas (ATIVA, BAIXADA, INAPTA, SUSPENSA, NULA).
  def status(value) = Normalization.key(text(value)).presence

  def uf(value)
    key = Normalization.key(text(value))
    UFS.include?(key) ? key : nil
  end

  # A BrasilAPI e o CNPJá mandam número, o CNPJ.ws manda "2062", o OpenCNPJ não manda código. Só vale o formato da
  # Receita: quatro dígitos.
  def legal_nature_code(value)
    return nil unless value.is_a?(String) || value.is_a?(Integer)

    digits = Normalization.digits(value)
    digits.length == LEGAL_NATURE_CODE_LENGTH ? digits.to_i : nil
  end

  def cnae(value)
    return nil unless value.is_a?(String) || value.is_a?(Integer)

    digits = Normalization.digits(value)
    digits.length == CNAE_LENGTH ? digits : nil
  end

  def date(value)
    raw = text(value)
    raw && Date.strptime(raw.first(DATE_LENGTH), '%Y-%m-%d')
  rescue Date::Error
    nil
  end

  # Menor (ou incapaz) por qualquer um dos três sinais da fonte, e a guarda não depende de a fonte preencher o texto:
  # - faixa que diz "menor" ou começa abaixo de 18. Faixa que cruza os 18 (13 a 20) conta como menor: na dúvida, a
  #   pessoa fica fora dos donos e do quadro gravado. O Orth deixava essa faixa como "não sei" e elegível;
  # - código da faixa da Receita 1 ou 2, mesmo com o texto vazio;
  # - representante legal de incapaz (mãe, pai, tutor, curador, assistente).
  def minor?(age_band, age_code: nil, representative: nil)
    minor_band?(age_band) || MINOR_AGE_CODES.include?(age_code_number(age_code)) ||
      INCAPABLE_REPRESENTATIVES.include?(Normalization.key(representative))
  end

  def minor_band?(age_band)
    key = Normalization.key(age_band)
    return true if key.include?('MENOR')

    ages = Normalization.numbers(key)
    ages.any? && ages.min < ADULT_AGE
  end

  def age_code_number(value)
    return nil unless value.is_a?(String) || value.is_a?(Integer)

    digits = Normalization.digits(value)
    digits.empty? ? nil : digits.to_i
  end

  # Qualificação do representante como texto ou como objeto { descricao } (OpenCNPJ e CNPJ.ws mandam os dois jeitos).
  def representative_qualification(*values)
    values.each do |value|
      found = text(value) || text(nested(value, 'descricao'))
      return found if found
    end
    nil
  end

  # [estado, membros]. Chave ausente é 'missing'; não-lista é 'malformed'; um membro ruim estraga o quadro inteiro.
  def qsa(container, key)
    return ['missing', []] unless container.key?(key)

    raw = container[key]
    return ['malformed', []] unless raw.is_a?(Array)
    return ['valid_empty', []] if raw.empty?

    members = raw.map { |value| record(value) && yield(value) }
    members.all? ? ['valid_nonempty', members] : ['malformed', []]
  end

  def malformed
    Registry::ParseResult.new(company: nil, reason: 'payload_malformed', qsa_state: 'malformed')
  end

  def build(provider:, requested_cnpj:, fetched_at:, parts:)
    qsa_state, members = parts.fetch(:qsa)
    attributes = company_attributes(provider, fetched_at, parts)
    reason = semantic_failure(requested_cnpj, attributes, qsa_state)
    company = reason ? nil : Registry::Company.new(**attributes, qsa: members)
    Registry::ParseResult.new(company: company, reason: reason, qsa_state: qsa_state)
  end

  def company_attributes(provider, fetched_at, parts)
    returned = cnpj(parts[:cnpj])
    {
      cnpj: returned, legal_name: text(parts[:legal_name]), trade_name: text(parts[:trade_name]), registration_status: status(parts[:status]),
      registration_state: uf(parts[:uf]), city: text(parts[:city]), legal_nature_code: legal_nature_code(parts[:nature_code]),
      legal_nature_text: text(parts[:nature_text]), opened_on: date(parts[:opened_on]), cnae: cnae(parts[:cnae]), provider: provider,
      sources: returned ? [{ 'provider' => provider, 'url' => Registry.source_url(provider, returned), 'fetched_at' => fetched_at.utc.iso8601 }] : []
    }
  end

  # Na ordem do Orth: identidade, depois conteúdo, depois quadro de sócios.
  def semantic_failure(requested_cnpj, attributes, qsa_state)
    identity_failure(requested_cnpj, attributes) || content_failure(attributes) || QSA_FAILURES[qsa_state]
  end

  def identity_failure(requested_cnpj, attributes)
    return 'cnpj_missing' unless attributes[:cnpj]

    'cnpj_mismatch' unless attributes[:cnpj] == requested_cnpj
  end

  def content_failure(attributes)
    return 'legal_name_missing' unless attributes[:legal_name]
    return 'status_missing' unless attributes[:registration_status]

    'establishment_address_missing' unless attributes[:city] && attributes[:registration_state]
  end
end
