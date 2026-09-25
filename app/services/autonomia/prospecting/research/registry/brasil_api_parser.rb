# BrasilAPI (https://brasilapi.com.br/api/cnpj/v1/<cnpj>). Porte de registry/brasil-api.ts do Orth.
# identificador_de_socio: 1 = pessoa jurídica, 2 = pessoa física, 3 = estrangeiro (fica UNKNOWN).
module Autonomia::Prospecting::Research::Registry::BrasilApiParser
  Support = Autonomia::Prospecting::Research::Registry::ParserSupport
  PERSON_TYPES = { 2 => 'PF', '2' => 'PF', 1 => 'PJ', '1' => 'PJ' }.freeze

  module_function

  def parse(requested_cnpj:, payload:, fetched_at:)
    payload = Support.record(payload)
    return Support.malformed unless payload

    Support.build(provider: 'BrasilAPI', requested_cnpj: requested_cnpj, fetched_at: fetched_at, parts: {
                    cnpj: payload['cnpj'], legal_name: payload['razao_social'], trade_name: payload['nome_fantasia'],
                    status: payload['descricao_situacao_cadastral'], city: payload['municipio'], uf: payload['uf'],
                    nature_code: payload['codigo_natureza_juridica'], nature_text: payload['natureza_juridica'],
                    opened_on: payload['data_inicio_atividade'], cnae: payload['cnae_fiscal'],
                    qsa: Support.qsa(payload, 'qsa') { |member| partner(member) }
                  })
  end

  def partner(member)
    name = Support.text(member['nome_socio'])
    return nil unless name && member.key?('identificador_de_socio')

    Autonomia::Prospecting::Research::Registry::Partner.build(
      name: name, qualification: member['qualificacao_socio'], person_type: PERSON_TYPES.fetch(member['identificador_de_socio'], 'UNKNOWN'),
      is_minor: Support.minor?(member['faixa_etaria']), entered_on: Support.date(member['data_entrada_sociedade'])
    )
  end
end
