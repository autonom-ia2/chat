# CNPJá, endpoint público e gratuito (https://open.cnpja.com/office/<cnpj>). Porte de registry/cnpja.ts do Orth.
# person.type: NATURAL = pessoa física, LEGAL = pessoa jurídica; o resto fica UNKNOWN.
module Autonomia::Prospecting::Research::Registry::CnpjaParser
  Support = Autonomia::Prospecting::Research::Registry::ParserSupport
  PERSON_TYPES = { 'NATURAL' => 'PF', 'LEGAL' => 'PJ' }.freeze

  module_function

  def parse(requested_cnpj:, payload:, fetched_at:)
    payload = Support.record(payload)
    company = Support.record(payload&.[]('company'))
    address = Support.record(payload&.[]('address'))
    return Support.malformed unless company && address

    Support.build(provider: 'CNPJá', requested_cnpj: requested_cnpj, fetched_at: fetched_at, parts: {
                    cnpj: payload['taxId'], legal_name: company['name'], trade_name: payload['alias'],
                    status: Support.nested(payload['status'], 'text'), city: address['city'], uf: address['state'],
                    nature_code: Support.nested(company['nature'], 'id'), nature_text: Support.nested(company['nature'], 'text'),
                    opened_on: payload['founded'], cnae: Support.nested(payload['mainActivity'], 'id'), phones: phones(payload['phones']),
                    qsa: Support.qsa(company, 'members') { |member| partner(member) }
                  })
  end

  # phones: [{ type, area, number }] (#679).
  def phones(values)
    return [] unless values.is_a?(Array)

    values.filter_map do |entry|
      entry = Support.record(entry)
      entry && Support.ddd_phone(entry['area'], entry['number'])
    end
  end

  def partner(member)
    person = Support.record(member['person'])
    name = Support.text(person&.[]('name'))
    return nil unless name && person.key?('type')

    representative = Support.nested(Support.record(member['agent'])&.[]('role'), 'text')

    Autonomia::Prospecting::Research::Registry::Partner.build(
      name: name, qualification: Support.nested(member['role'], 'text'), person_type: PERSON_TYPES.fetch(person['type'], 'UNKNOWN'),
      is_minor: Support.minor?(person['age'], representative: representative), entered_on: Support.date(member['since'])
    )
  end
end
