# Cargo pedido para a pesquisa do decisor (porte de requested-role.ts do Orth, #679). O chat2you grava a chave do
# DecisionMakerType ('owner', 'ceo'...); o Orth recebia o rótulo em português. Os dois valem, por comparação normalizada
# contra tabela fechada. Vazio cai no Proprietário. Qualquer outra coisa é recusada, para não virar busca genérica.
class Autonomia::Prospecting::Research::RequestedRole
  Normalization = Autonomia::Prospecting::Research::Normalization

  EXPLICIT_ROLE_LABELS = {
    'CEO' => 'ceo', 'Comercial' => 'commercial', 'Financeiro' => 'financial', 'Marketing' => 'marketing', 'RH' => 'hr',
    'Operações' => 'operations', 'Tecnologia' => 'technology', 'Jurídico' => 'legal', 'Compliance' => 'compliance',
    'Riscos' => 'risk'
  }.freeze
  OWNER_ALIASES = ['owner', 'proprietario', 'socio proprietario'].to_set { |value| Normalization.key(value) }.freeze
  EXPLICIT_BY_KEY = EXPLICIT_ROLE_LABELS.flat_map { |label, key| [[Normalization.key(label), key], [Normalization.key(key), key]] }
                                        .to_h.freeze

  class Invalid < StandardError
    def code = 'INVALID_REQUESTED_ROLE'

    def initialize = super(code)
  end

  attr_reader :classification, :role_key

  def self.resolve(value)
    normalized = Normalization.key(value)
    return new(:owner, 'owner') if normalized.empty? || OWNER_ALIASES.include?(normalized)

    role_key = EXPLICIT_BY_KEY[normalized]
    raise Invalid unless role_key

    new(:explicit_role, role_key)
  end

  def initialize(classification, role_key)
    @classification = classification
    @role_key = role_key
    freeze
  end

  def owner?
    classification == :owner
  end
end
