require 'rails_helper'

# Porte de registry/parsers.test.ts do Orth, com as fixtures dele (spec/fixtures/prospecting/registry).
# Diferenças do porte, de propósito: o representante legal é descartado (não está na lista fechada de campos de pessoa
# física), a qualificação chega com rótulo canônico, e faixa etária que cruza os 18 anos conta como menor.
RSpec.describe Autonomia::Prospecting::Research::Registry::ParserSupport do
  let(:registry) { Autonomia::Prospecting::Research::Registry }
  let(:fetched_at) { Time.zone.parse('2026-07-26T12:00:00Z') }

  def fixture(name)
    JSON.parse(Rails.root.join('spec/fixtures/prospecting/registry', "#{name}.json").read)
  end

  def parse(parser, payload)
    parser.parse(requested_cnpj: '11222333000181', payload: payload, fetched_at: fetched_at)
  end

  {
    'OpenCNPJ' => ['OpenCnpjParser', 'opencnpj-success', ['EMPRESA ALFA SINTETICA LTDA', 'ALFA SINTETICA', 'SAO PAULO', 'SP']],
    'BrasilAPI' => ['BrasilApiParser', 'brasilapi-success', ['EMPRESA BETA SINTETICA LTDA', 'BETA SINTETICA', 'RIO DE JANEIRO', 'RJ']],
    'CNPJ.ws' => ['CnpjWsParser', 'cnpjws-success', ['EMPRESA GAMA SINTETICA LTDA', 'GAMA SINTETICA', 'BELO HORIZONTE', 'MG']],
    'CNPJá' => ['CnpjaParser', 'cnpja-success', ['EMPRESA DELTA SINTETICA LTDA', 'DELTA SINTETICA', 'BRASILIA', 'DF']]
  }.each do |provider, (parser_name, fixture_name, (legal_name, trade_name, city, uf))|
    it "lê os campos normalizados do #{provider} pelos caminhos oficiais" do
      result = parse(registry.const_get(parser_name), fixture(fixture_name))
      company = result.company

      expect(result).to be_valid
      expect(result.reason).to be_nil
      expect(company).to have_attributes(
        cnpj: '11222333000181', legal_name: legal_name, trade_name: trade_name, registration_status: 'ATIVA',
        registration_state: uf, city: city, provider: provider
      )
      expect(company.qsa.size).to eq(3)
      expect(company.qsa.map(&:person_type)).to eq(%w[PF PJ UNKNOWN])
      expect(company.sources).to eq([{ 'provider' => provider, 'url' => registry.source_url(provider, '11222333000181'),
                                       'fetched_at' => '2026-07-26T12:00:00Z' }])
    end
  end

  it 'guarda qualificação canônica e a flag de menor, sem promover UNKNOWN a PF' do
    qsa = parse(registry::OpenCnpjParser, fixture('opencnpj-success')).company.qsa

    expect(qsa[0]).to have_attributes(name: 'PESSOA FISICA SINTETICA', person_type: 'PF', qualification: 'Sócio-Administrador',
                                      qualification_key: 'SOCIO ADMINISTRADOR', is_minor: false)
    expect(qsa[2]).to have_attributes(person_type: 'UNKNOWN')
  end

  it 'marca menor quando a faixa prova idade abaixo de 18' do
    expect(parse(registry::BrasilApiParser, fixture('brasilapi-success')).company.qsa[0])
      .to have_attributes(person_type: 'PF', is_minor: true)
  end

  it 'marca menor quando a faixa cruza os 18 anos (13 a 20): na dúvida, fora do quadro de donos' do
    expect(parse(registry::OpenCnpjParser, fixture('opencnpj-success')).company.qsa[2].is_minor).to be(true)
  end

  it 'não marca menor quando a faixa é toda adulta ou não diz idade' do
    payload = fixture('opencnpj-success')
    payload['QSA'][0]['faixa_etaria'] = 'Não se aplica'

    expect(parse(registry::OpenCnpjParser, payload).company.qsa[0].is_minor).to be(false)
    expect(parse(registry::CnpjaParser, fixture('cnpja-success')).company.qsa[0].is_minor).to be(false)
  end

  it 'lê a qualificação aninhada do CNPJ.ws e o papel do CNPJá' do
    expect(parse(registry::CnpjWsParser, fixture('cnpjws-success')).company.qsa[0].qualification).to eq('Sócio-Administrador')
    expect(parse(registry::CnpjaParser, fixture('cnpja-success')).company.qsa[1].qualification).to eq('Sócio')
  end

  it 'descarta o representante legal e todo campo de pessoa física fora da lista fechada' do
    company = parse(registry::OpenCnpjParser, fixture('opencnpj-contrato-real')).company
    partner = company.qsa[0]

    expect(partner.to_h.keys).to match_array(%i[name qualification qualification_key person_type is_minor entered_on])
    expect(partner.entered_on).to eq(Date.new(2023, 12, 11))
    serialized = company.storable_qsa.to_json
    expect(serialized).not_to include('208478', 'REPRESENTANTE', 'Procurador', '71 a 80')
    expect(company.storable_qsa.first).to eq('name' => 'PESSOA FISICA SINTETICA', 'qualification' => 'Sócio-Administrador',
                                             'entered_on' => '2023-12-11')
  end

  it 'nunca guarda menor no quadro gravável' do
    company = parse(registry::BrasilApiParser, fixture('brasilapi-success')).company

    expect(company.qsa.map(&:name)).to include('PESSOA FISICA BRASIL API')
    expect(company.storable_qsa.pluck('name')).not_to include('PESSOA FISICA BRASIL API')
    expect(company.storable_qsa).to include('name' => 'PESSOA JURIDICA BRASIL API', 'qualification' => 'Sócio',
                                            'entered_on' => nil, 'person_type' => 'PJ')
  end

  # Regressão medida em produção no Orth (2026-07-30): a fixture inventada usava o código numérico e o OpenCNPJ real
  # devolve o rótulo. Todo sócio virava UNKNOWN e a taxa de acerto foi 0,0%.
  it 'lê o contrato real do OpenCNPJ: rótulo de pessoa' do
    qsa = parse(registry::OpenCnpjParser, fixture('opencnpj-contrato-real')).company.qsa

    expect(qsa[0]).to have_attributes(name: 'PESSOA FISICA SINTETICA', person_type: 'PF', qualification: 'Sócio-Administrador')
    expect(qsa[1]).to have_attributes(name: 'PESSOA JURIDICA SINTETICA', person_type: 'PJ')
  end

  it 'continua aceitando o código numérico da Receita' do
    expect(parse(registry::OpenCnpjParser, fixture('opencnpj-success')).company.qsa.map(&:person_type)).to eq(%w[PF PJ UNKNOWN])
  end

  {
    'vazio' => [[], 'valid_empty', true],
    'ausente' => [:absent, 'missing', false],
    'malformado' => [{ 'invalid' => true }, 'malformed', false],
    'membro malformado' => [[{ 'identificador_socio' => 2 }], 'malformed', false]
  }.each do |label, (qsa, state, valid)|
    it "distingue QSA #{label} no OpenCNPJ" do
      payload = fixture('opencnpj-success')
      qsa == :absent ? payload.delete('QSA') : payload['QSA'] = qsa

      result = parse(registry::OpenCnpjParser, payload)
      expect(result.qsa_state).to eq(state)
      expect(result.valid?).to be(valid)
    end
  end

  it 'invalida o provedor que devolve CNPJ diferente do pedido' do
    result = parse(registry::OpenCnpjParser, fixture('opencnpj-success').merge('cnpj' => '22.333.444/0001-55'))

    expect(result).not_to be_valid
    expect(result.reason).to eq('cnpj_mismatch')
  end

  it 'recusa cadastro sem cidade ou UF do estabelecimento' do
    payload = fixture('cnpjws-success')
    payload['estabelecimento']['cidade'] = nil

    expect(parse(registry::CnpjWsParser, payload).reason).to eq('establishment_address_missing')
  end

  it 'recusa corpo que não é objeto' do
    expect(parse(registry::CnpjaParser, nil).reason).to eq('payload_malformed')
    expect(parse(registry::CnpjWsParser, { 'razao_social' => 'X' }).reason).to eq('payload_malformed')
  end

  it 'lê natureza jurídica, abertura e CNAE de cada provedor' do
    brasil = fixture('brasilapi-success').merge('codigo_natureza_juridica' => 2135, 'natureza_juridica' => 'Empresário (Individual)',
                                                'data_inicio_atividade' => '2015-03-04', 'cnae_fiscal' => 4_721_102)
    ws = fixture('cnpjws-success').merge('natureza_juridica' => { 'id' => '2062', 'descricao' => 'Sociedade Empresária Limitada' })
    ws['estabelecimento'].merge!('data_inicio_atividade' => '2001-05-10', 'atividade_principal' => { 'id' => '4721102' })
    cnpja = fixture('cnpja-success').merge('founded' => '1999-01-31', 'mainActivity' => { 'id' => 4_721_102 })
    cnpja['company']['nature'] = { 'id' => 2062, 'text' => 'Sociedade Empresária Limitada' }
    open = fixture('opencnpj-success').merge('natureza_juridica' => 'Empresário (Individual)', 'cnae_principal' => '4721102')

    expect(parse(registry::BrasilApiParser, brasil).company)
      .to have_attributes(legal_nature_code: 2135, legal_nature_text: 'Empresário (Individual)', opened_on: Date.new(2015, 3, 4),
                          cnae: '4721102')
    expect(parse(registry::CnpjWsParser, ws).company).to have_attributes(legal_nature_code: 2062, opened_on: Date.new(2001, 5, 10),
                                                                         cnae: '4721102')
    expect(parse(registry::CnpjaParser, cnpja).company).to have_attributes(legal_nature_code: 2062, cnae: '4721102')
    expect(parse(registry::OpenCnpjParser, open).company).to have_attributes(legal_nature_code: nil, legal_nature_text: 'Empresário (Individual)')
  end

  it 'mantém a situação cadastral específica da Receita, sem acento' do
    payload = fixture('brasilapi-success').merge('descricao_situacao_cadastral' => 'Baixada')

    expect(parse(registry::BrasilApiParser, payload).company.registration_status).to eq('BAIXADA')
  end

  it 'monta os atributos do perfil de empresa com o quadro gravável' do
    company = parse(registry::OpenCnpjParser, fixture('opencnpj-contrato-real')).company

    expect(company.profile_attributes).to include(
      'cnpj' => '11222333000181', 'legal_name' => 'EMPRESA ALFA SINTETICA LTDA', 'registration_status' => 'ATIVA',
      'registration_state' => 'SP', 'qsa' => company.storable_qsa, 'sources' => company.sources
    )
    expect(company.profile_attributes['data']).to include('city' => 'SAO PAULO', 'provider' => 'OpenCNPJ')
  end
end
