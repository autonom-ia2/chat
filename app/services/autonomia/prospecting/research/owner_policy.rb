# Regra do dono (porte de owner-policy.ts do Orth, #679): quem decide a compra, lido do quadro de sócios, sem IA.
#
# Ordem: pessoa física adulta com vínculo societário (sócio-administrador, sócio, titular...) primeiro; cargo de comando
# sem vínculo provado (administrador, diretor, presidente, CEO) depois. Dentro de cada faixa, a ordem do provedor.
# owners.first é o decisor do lead. Sem ninguém no quadro, o Empresário Individual (natureza 2135) é nomeado pela razão
# social, que por lei é o nome civil do titular (art. 1.156 do Código Civil). O gatilho é a natureza jurídica, nunca a
# cara do texto: uma autarquia também tem razão social sem sufixo de empresa.
#
# Sem decisor, reason diz por quê, num código de REASONS (a tela tem um texto para cada).
module Autonomia::Prospecting::Research::OwnerPolicy
  Normalization = Autonomia::Prospecting::Research::Normalization

  OWNER_QUALIFICATIONS = Set[
    'SOCIO ADMINISTRADOR', 'SOCIO', 'TITULAR', 'TITULAR PESSOA FISICA RESIDENTE OU DOMICILIADO NO BRASIL',
    'EMPRESARIO INDIVIDUAL', 'PROPRIETARIO', 'ACIONISTA CONTROLADOR'
  ].freeze
  # Decisão do CEO do Orth em 2026-07-30: a régua é "quem manda no negócio", não "prova de propriedade".
  EXECUTIVE_QUALIFICATIONS = Set['ADMINISTRADOR', 'DIRETOR', 'PRESIDENTE', 'CEO'].freeze

  SOLE_PROPRIETOR_NATURE_CODE = 2135
  SOLE_PROPRIETOR_NATURE_KEY = 'EMPRESARIO INDIVIDUAL'.freeze
  SOLE_PROPRIETOR_QUALIFICATION = 'Empresário Individual'.freeze
  # Naturezas 1xxx da Receita: administração pública. O OpenCNPJ só manda o texto, que começa por um destes.
  PUBLIC_NATURE_CODES = (1000..1999)
  PUBLIC_NATURE_PREFIXES = [
    'ORGAO PUBLICO', 'AUTARQUIA', 'FUNDACAO PUBLICA', 'CONSORCIO PUBLICO', 'FUNDO PUBLICO', 'ESTADO OU DISTRITO FEDERAL',
    'MUNICIPIO', 'COMISSAO POLINACIONAL'
  ].freeze
  # Caracteres de número que o MEI carrega na razão social (raiz do CNPJ na frente, CPF no fim).
  NUMBER_CHARS = (('0'..'9').to_a + %w[. - /]).to_set.freeze

  REASONS = %w[explicit_role_not_supported public_entity no_qsa only_companies only_minors no_eligible_role].freeze

  Selection = Data.define(:owners, :reason, :evidence) do
    def decision = owners.first

    def storable_owners = owners.map { |owner| Autonomia::Prospecting::Research::PersonFields.storable!(owner) }
  end

  module_function

  def select(company:, requested_role:)
    return none('explicit_role_not_supported') unless Autonomia::Prospecting::Research::RequestedRole.resolve(requested_role).owner?

    owners = qsa_owners(company.qsa)
    return Selection.new(owners: owners, reason: nil, evidence: :qsa) if owners.any?

    sole = sole_proprietor(company)
    return Selection.new(owners: [sole], reason: nil, evidence: :legal_name) if sole

    none(no_decision_reason(company))
  end

  def qsa_owners(qsa)
    eligible = qsa.select { |partner| adult_person?(partner) }
    owners = eligible.select { |partner| OWNER_QUALIFICATIONS.include?(partner.qualification_key) }
    executives = eligible.select { |partner| EXECUTIVE_QUALIFICATIONS.include?(partner.qualification_key) }
    (owners + executives).map { |partner| owner(partner.name, partner.qualification) }
  end

  def sole_proprietor(company)
    return nil unless sole_proprietor_nature?(company)

    name = holder_name(company.legal_name)
    name && owner(name, SOLE_PROPRIETOR_QUALIFICATION)
  end

  def sole_proprietor_nature?(company)
    company.legal_nature_code == SOLE_PROPRIETOR_NATURE_CODE ||
      Normalization.key(company.legal_nature_text) == SOLE_PROPRIETOR_NATURE_KEY
  end

  # Tira da razão social os números da ponta ("12.345.678 FULANO" e "FULANO 12345678901" viram "FULANO").
  def holder_name(legal_name)
    number = ->(token) { token.each_char.all? { |char| NUMBER_CHARS.include?(char) } }
    tokens = legal_name.to_s.split.drop_while(&number).reverse.drop_while(&number).reverse
    tokens.join(' ').presence
  end

  def no_decision_reason(company)
    return 'public_entity' if public_entity?(company)
    return 'no_qsa' if company.qsa.empty?

    qsa_reason(company.qsa)
  end

  # Adulto PF sem cargo de comando, só menor, ou só empresa sócia. Estrangeiro e tipo desconhecido também caem em
  # "nenhum cargo elegível".
  def qsa_reason(qsa)
    return 'no_eligible_role' if qsa.any? { |partner| adult_person?(partner) }
    return 'only_minors' if qsa.any? { |partner| minor_person?(partner) }

    qsa.all?(&:company?) ? 'only_companies' : 'no_eligible_role'
  end

  def adult_person?(partner) = partner.natural_person? && !partner.is_minor

  def minor_person?(partner) = !partner.company? && partner.is_minor

  def public_entity?(company)
    return PUBLIC_NATURE_CODES.cover?(company.legal_nature_code) if company.legal_nature_code

    key = Normalization.key(company.legal_nature_text)
    PUBLIC_NATURE_PREFIXES.any? { |prefix| key.start_with?(prefix) }
  end

  def owner(name, qualification) = { 'name' => name, 'qualification' => qualification }.freeze

  def none(reason) = Selection.new(owners: [], reason: reason, evidence: nil)
end
