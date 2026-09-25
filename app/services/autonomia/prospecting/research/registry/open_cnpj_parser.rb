# OpenCNPJ (https://api.opencnpj.org/<cnpj>). Porte de registry/open-cnpj.ts do Orth.
#
# O identificador do sócio vem como rótulo ("Pessoa Física"), não como o código da Receita. No Orth, ler só o código
# fez todo sócio virar UNKNOWN e a taxa de acerto cair a 0,0% em 100 leads reais (2026-07-30). Os dois formatos valem.
# O OpenCNPJ não manda o código da natureza jurídica, só a descrição.
module Autonomia::Prospecting::Research::Registry::OpenCnpjParser
  Support = Autonomia::Prospecting::Research::Registry::ParserSupport
  PERSON_TYPES = { 2 => 'PF', '2' => 'PF', 1 => 'PJ', '1' => 'PJ', 'PESSOA FISICA' => 'PF', 'PESSOA JURIDICA' => 'PJ' }.freeze

  module_function

  def parse(requested_cnpj:, payload:, fetched_at:)
    payload = Support.record(payload)
    return Support.malformed unless payload

    Support.build(provider: 'OpenCNPJ', requested_cnpj: requested_cnpj, fetched_at: fetched_at, parts: {
                    cnpj: payload['cnpj'], legal_name: payload['razao_social'], trade_name: payload['nome_fantasia'],
                    status: payload['situacao_cadastral'], city: payload['municipio'], uf: payload['uf'],
                    nature_code: nil, nature_text: payload['natureza_juridica'], opened_on: payload['data_inicio_atividade'],
                    cnae: payload['cnae_principal'], qsa: Support.qsa(payload, 'QSA') { |member| partner(member) }
                  })
  end

  def partner(member)
    name = Support.text(member['nome_socio'])
    return nil unless name && member.key?('identificador_socio')

    Autonomia::Prospecting::Research::Registry::Partner.build(
      name: name, qualification: member['qualificacao_socio'], person_type: person_type(member['identificador_socio']),
      is_minor: minor?(member), entered_on: Support.date(member['data_entrada_sociedade'])
    )
  end

  # O representante vem em qualificacao_representante (objeto { codigo, descricao }) ou no nome antigo, como no Orth.
  def minor?(member)
    representative = Support.representative_qualification(member['qualificacao_representante'], member['qualificacao_representante_legal'])
    Support.minor?(member['faixa_etaria'], age_code: member['codigo_faixa_etaria'], representative: representative)
  end

  def person_type(value)
    PERSON_TYPES[value.is_a?(String) ? Autonomia::Prospecting::Research::Normalization.key(value) : value] || 'UNKNOWN'
  end
end
