# CNPJ.ws (https://publica.cnpj.ws/cnpj/<cnpj>). Porte de registry/cnpj-ws.ts do Orth. O endereço e o CNPJ ficam em
# estabelecimento; a qualificação vem como objeto { descricao } ou, às vezes, como texto solto.
module Autonomia::Prospecting::Research::Registry::CnpjWsParser
  Support = Autonomia::Prospecting::Research::Registry::ParserSupport
  PERSON_TYPES = { 'PESSOA FISICA' => 'PF', 'PESSOA JURIDICA' => 'PJ' }.freeze

  module_function

  def parse(requested_cnpj:, payload:, fetched_at:)
    payload = Support.record(payload)
    establishment = Support.record(payload&.[]('estabelecimento'))
    return Support.malformed unless establishment

    Support.build(provider: 'CNPJ.ws', requested_cnpj: requested_cnpj, fetched_at: fetched_at, parts: {
                    cnpj: establishment['cnpj'], legal_name: payload['razao_social'], trade_name: establishment['nome_fantasia'],
                    status: establishment['situacao_cadastral'], city: Support.nested(establishment['cidade'], 'nome'),
                    uf: Support.nested(establishment['estado'], 'sigla'), nature_code: Support.nested(payload['natureza_juridica'], 'id'),
                    nature_text: Support.nested(payload['natureza_juridica'], 'descricao'),
                    opened_on: establishment['data_inicio_atividade'], cnae: Support.nested(establishment['atividade_principal'], 'id'),
                    qsa: Support.qsa(payload, 'socios') { |member| partner(member) }
                  })
  end

  def partner(member)
    name = Support.text(member['nome'])
    return nil unless name && member.key?('tipo')

    qualification = member['qualificacao_socio']
    representative = Support.representative_qualification(member['qualificacao_representante'])
    Autonomia::Prospecting::Research::Registry::Partner.build(
      name: name, qualification: Support.text(qualification) || Support.nested(qualification, 'descricao'),
      person_type: PERSON_TYPES.fetch(Autonomia::Prospecting::Research::Normalization.key(member['tipo']), 'UNKNOWN'),
      is_minor: Support.minor?(member['faixa_etaria'], representative: representative), entered_on: Support.date(member['data_entrada'])
    )
  end
end
