# Monta o perfil da empresa a partir do cadastro e da regra do dono (#679), na fronteira com o banco.
#
# Da pessoa física só passa a lista fechada de Research::PersonFields::ALLOWED. Não é um recorte que descarta calado:
# um campo de pessoa a mais vindo da montagem levanta Violation, e a pesquisa vira falha sem gravar nada. Menor de idade
# nunca entra, mesmo que a fonte o traga.
module Autonomia::Prospecting::Research::ProfileAttributes
  PERSON_CLASSIFICATION_KEYS = %w[person_type is_minor].freeze

  module_function

  def build(company, selection:, requested_role:, verified_at:)
    {
      cnpj: digits(company.cnpj), legal_name: company.legal_name, trade_name: company.trade_name,
      registration_status: company.registration_status, registration_state: company.registration_state,
      legal_nature_code: company.legal_nature_code&.to_s, legal_nature_text: company.legal_nature_text,
      data: {
        'opened_on' => company.opened_on&.to_s, 'cnae' => company.cnae, 'requested_role' => requested_role,
        'no_decision_reason' => selection.reason&.to_s, 'decision_source' => selection.evidence&.to_s
      },
      qsa: partners(company.qsa), owners: owners(selection.owners), sources: Array(company.sources).as_json, verified_at: verified_at
    }
  end

  # Nome e qualificação de cada dono, na ordem da regra do dono; dono sem nome não é dono.
  def owners(list)
    Array(list).filter_map do |owner|
      attributes = person!(owner.to_h.transform_keys(&:to_s))
      attributes.slice('name', 'qualification') if attributes['name'].present?
    end
  end

  def partners(qsa)
    Array(qsa).reject { |partner| partner.is_minor == true }.map do |partner|
      next company_partner(partner) if partner.person_type.to_s.strip.upcase == 'PJ'

      person!(partner.to_h.transform_keys(&:to_s).except(*PERSON_CLASSIFICATION_KEYS)).merge('entered_on' => partner.entered_on&.to_s)
    end
  end

  def company_partner(partner)
    { 'name' => partner.name, 'qualification' => partner.qualification, 'entered_on' => partner.entered_on&.to_s, 'person_type' => 'PJ' }
  end

  def person!(attributes)
    extra = attributes.keys - Autonomia::Prospecting::Research::PersonFields::ALLOWED
    raise Autonomia::Prospecting::Research::PersonFields::Violation, "campos fora da lista: #{extra.sort.join(', ')}" if extra.any?

    attributes
  end

  def digits(value)
    value.to_s.each_char.select { |char| char.between?('0', '9') }.join
  end
end
