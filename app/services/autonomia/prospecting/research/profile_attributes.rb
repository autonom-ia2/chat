# Monta o perfil da empresa a partir do cadastro (Registry::Company) e da regra do dono (OwnerPolicy::Selection), na
# fronteira com o banco (#679).
#
# Da pessoa física só passa a lista fechada de Research::PersonFields::ALLOWED. Não é um recorte que descarta calado:
# um campo de pessoa a mais vindo da montagem levanta Violation, e a pesquisa vira falha sem gravar nada. A frente B já
# confere cada sócio em Partner#storable; esta fronteira confere de novo o que vai para o banco, sem depender dela.
# Menor de idade nunca entra, mesmo que a fonte o traga.
#
# No Empresário Individual (MEI incluso) a razão social da Receita carrega o CPF do titular no fim ("FULANO 12345678909").
# O que se grava e se mostra é a razão social sem os números das pontas, o mesmo nome que a regra do dono usa. A
# original só vive em memória, no matcher da descoberta.
module Autonomia::Prospecting::Research::ProfileAttributes
  PersonFields = Autonomia::Prospecting::Research::PersonFields
  OwnerPolicy = Autonomia::Prospecting::Research::OwnerPolicy

  module_function

  def build(company, selection:, requested_role:, verified_at:)
    {
      cnpj: digits(company.cnpj), legal_name: legal_name(company), trade_name: company.trade_name,
      registration_status: company.registration_status, registration_state: company.registration_state,
      legal_nature_code: company.legal_nature_code&.to_s, legal_nature_text: company.legal_nature_text,
      data: {
        'city' => company.city, 'opened_on' => company.opened_on&.to_s, 'cnae' => company.cnae, 'provider' => company.provider,
        'requested_role' => requested_role, 'no_decision_reason' => selection.reason&.to_s, 'decision_source' => selection.evidence&.to_s
      },
      qsa: partners(company.qsa), owners: owners(selection.owners), sources: Array(company.sources).as_json, verified_at: verified_at
    }
  end

  def legal_name(company)
    OwnerPolicy.sole_proprietor_nature?(company) ? OwnerPolicy.holder_name(company.legal_name) : company.legal_name
  end

  # Nome e qualificação de cada dono, na ordem da regra do dono; dono sem nome não é dono.
  def owners(list)
    Array(list).filter_map do |owner|
      attributes = PersonFields.storable!(owner)
      attributes.slice('name', 'qualification') if attributes['name'].present?
    end
  end

  # Empresa sócia leva o tipo junto e não é pessoa; pessoa física (ou tipo desconhecido) passa pela lista fechada.
  def partners(qsa)
    Array(qsa).reject(&:is_minor).map do |partner|
      entry = partner.storable
      partner.company? ? entry : PersonFields.storable!(entry)
    end
  end

  def digits(value)
    value.to_s.each_char.select { |char| char.between?('0', '9') }.join
  end
end
