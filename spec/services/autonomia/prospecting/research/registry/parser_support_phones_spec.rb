require 'rails_helper'

# Telefone do cadastro público (#679, decisão do Rodrigo de 25/09: ir além do Orth). O Orth deixa o telefone do
# cadastro vazio (registry/parser-utils.ts), e empresa certa com nome diferente do Google era recusada mesmo com o
# telefone idêntico: na prova real em Guarapuava, 3 de 20. Aqui cada fonte lê o telefone no formato que ela manda
# (conferido nas quatro APIs reais em 25/09), o fax fica de fora, e o telefone vira sinal do matcher e fica gravado
# no perfil da empresa. Números abaixo são sintéticos.
RSpec.describe Autonomia::Prospecting::Research::Registry::ParserSupport, '.phones' do
  let(:registry) { Autonomia::Prospecting::Research::Registry }
  let(:fetched_at) { Time.zone.parse('2026-09-25T12:00:00Z') }

  def fixture(name)
    JSON.parse(Rails.root.join('spec/fixtures/prospecting/registry', "#{name}.json").read)
  end

  def parse(parser, payload)
    registry.const_get(parser).parse(requested_cnpj: '11222333000181', payload: payload, fetched_at: fetched_at).company
  end

  describe 'leitura em cada fonte' do
    it 'lê ddd_telefone_1 e ddd_telefone_2 da BrasilAPI e ignora o fax e o vazio' do
      payload = fixture('brasilapi-success').merge('ddd_telefone_1' => '4230351935', 'ddd_telefone_2' => '',
                                                   'ddd_fax' => '4230359999')

      expect(parse('BrasilApiParser', payload).phones).to eq(['554230351935'])
    end

    it 'lê a lista telefones do OpenCNPJ e deixa o fax de fora' do
      payload = fixture('opencnpj-success').merge('telefones' => [
                                                    { 'ddd' => '42', 'numero' => '30351935', 'is_fax' => false },
                                                    { 'ddd' => '42', 'numero' => '30359999', 'is_fax' => true }
                                                  ])

      expect(parse('OpenCnpjParser', payload).phones).to eq(['554230351935'])
    end

    it 'lê ddd1/telefone1 e ddd2/telefone2 do estabelecimento no CNPJ.ws' do
      payload = fixture('cnpjws-success')
      payload['estabelecimento'] = payload['estabelecimento'].merge(
        'ddd1' => '42', 'telefone1' => '30351935', 'ddd2' => '42', 'telefone2' => '991092006', 'ddd_fax' => '42', 'fax' => '30359999'
      )

      expect(parse('CnpjWsParser', payload).phones).to eq(%w[554230351935 5542991092006])
    end

    it 'lê a lista phones do CNPJá' do
      payload = fixture('cnpja-success').merge('phones' => [{ 'type' => 'LANDLINE', 'area' => '42', 'number' => '30351935' }])

      expect(parse('CnpjaParser', payload).phones).to eq(['554230351935'])
    end

    it 'descarta número que não é telefone válido e repetido, sem derrubar o cadastro' do
      payload = fixture('brasilapi-success').merge('ddd_telefone_1' => '4230351935', 'ddd_telefone_2' => '4230351935')
      expect(parse('BrasilApiParser', payload).phones).to eq(['554230351935'])

      invalid = fixture('brasilapi-success').merge('ddd_telefone_1' => '12', 'ddd_telefone_2' => nil)
      company = parse('BrasilApiParser', invalid)
      expect(company).to be_present
      expect(company.phones).to eq([])
    end

    it 'fonte sem campo de telefone devolve lista vazia' do
      expect(parse('BrasilApiParser', fixture('brasilapi-success').except('ddd_telefone_1', 'ddd_telefone_2')).phones).to eq([])
    end

    it 'deixa de fora o fax marcado como texto no OpenCNPJ e como tipo no CNPJá' do
      open_cnpj = fixture('opencnpj-success').merge('telefones' => [{ 'ddd' => '42', 'numero' => '30359999', 'is_fax' => 'true' }])
      cnpja = fixture('cnpja-success').merge('phones' => [{ 'type' => 'FAX', 'area' => '42', 'number' => '30359999' }])

      expect(parse('OpenCnpjParser', open_cnpj).phones).to eq([])
      expect(parse('CnpjaParser', cnpja).phones).to eq([])
    end

    it 'só trata como fax o que o OpenCNPJ marca como fax de fato' do
      payload = fixture('opencnpj-success').merge('telefones' => [{ 'ddd' => '42', 'numero' => '30351935', 'is_fax' => 'no' }])

      expect(parse('OpenCnpjParser', payload).phones).to eq(['554230351935'])
    end

    it 'não repete o DDD quando o número já vem com ele' do
      payload = fixture('cnpja-success').merge('phones' => [{ 'type' => 'LANDLINE', 'area' => '42', 'number' => '4230351935' }])

      expect(parse('CnpjaParser', payload).phones).to eq(['554230351935'])
    end
  end

  it 'grava os telefones no perfil da empresa pelo caminho que o Runner usa' do
    company = parse('BrasilApiParser', fixture('brasilapi-success').merge('ddd_telefone_1' => '4230351935'))
    selection = Autonomia::Prospecting::Research::OwnerPolicy.select(company: company, requested_role: 'owner')
    attributes = Autonomia::Prospecting::Research::ProfileAttributes.build(
      company, selection: selection, requested_role: 'owner', verified_at: Time.current
    )

    expect(attributes[:data]).to include('phones' => ['554230351935'])
  end

  describe 'confirmação da empresa pelo telefone' do
    let(:adapter) { Autonomia::Prospecting::Research::MatcherAdapter }
    let(:matcher) { Autonomia::Prospecting::Research::IdentityMatcher }
    let(:cnpj) { '11222333000181' }
    # Caso real reduzido: Google "Goes Contabilidade Guarapuava | Escritório de Contabilidade", cadastro
    # "GOES CONTABILIDADE LTDA", BigDataCorp dando 70% de semelhança de nome.
    let(:place) do
      matcher::Place.new(name: 'Goes Contabilidade Guarapuava | Escritório de Contabilidade', city: 'Guarapuava', uf: 'PR',
                         phone: '+55 42 3035-1935', website: nil)
    end

    def bdc_candidate
      Autonomia::Prospecting::Research::BigDataCorpDiscovery::Candidate.new(
        cnpj: cnpj, name: 'GOES CONTABILIDADE LTDA', trade_name: nil, status: 'ATIVA', official_name_percentage: 70,
        trade_name_percentage: nil, is_headquarter: true, headquarter_state: 'PR', match_keys: [], provider_index: 0
      )
    end

    def identity(phones:)
      adapter::Identity.new(cnpj: cnpj, legal_name: 'GOES CONTABILIDADE LTDA', trade_name: nil, status: 'ATIVA',
                            city: 'GUARAPUAVA', uf: 'PR', domain: nil, phones: phones)
    end

    def decide(phones)
      matcher.match(place, [adapter.adapt(bdc_candidate, identity(phones: phones)).candidate]).to_h
    end

    it 'aceita com nome de 70% quando o telefone do cadastro é o do Google' do
      expect(decide(['554230351935'])).to include(decision: :accept, accepted_cnpj: cnpj, reason: 'phone_primary_name_065_plus_city_uf')
    end

    it 'aceita quando o telefone que bate é o segundo do cadastro' do
      expect(decide(%w[554299999999 554230351935])).to include(decision: :accept)
    end

    it 'sem o telefone do cadastro, o mesmo nome continua recusado (comportamento do Orth)' do
      expect(decide([])).to include(decision: :not_found, reason: 'no_qualified_candidate')
    end

    it 'telefone diferente não ajuda' do
      expect(decide(['554299999999'])).to include(decision: :not_found)
    end

    # O lead é o escritório de contabilidade; dois clientes dele têm o telefone do escritório no próprio CNPJ.
    it 'telefone igual em mais de um candidato não vale como sinal forte para nenhum' do
      client = lambda do |cnpj_value, percentage|
        Autonomia::Prospecting::Research::IdentityMatcher::Candidate.new(
          cnpj: cnpj_value, name: 'CLIENTE', city: 'GUARAPUAVA', uf: 'PR', phone: ['554230351935'], domain: nil,
          status: 'ATIVA', match_score: percentage, name_similarity: percentage
        )
      end

      result = matcher.match(place, [client.call('11444777000161', 0.72), client.call('11222333000181', 0.66)]).to_h

      expect(result).to include(decision: :not_found, reason: 'no_qualified_candidate')
    end

    # O dono fechou o CNPJ antigo e abriu outro com o mesmo telefone: o inativo não tira o sinal do certo.
    it 'candidato já rejeitado não conta como telefone compartilhado' do
      build = lambda do |cnpj_value, percentage, status|
        Autonomia::Prospecting::Research::IdentityMatcher::Candidate.new(
          cnpj: cnpj_value, name: 'GOES CONTABILIDADE LTDA', city: 'GUARAPUAVA', uf: 'PR', phone: ['554230351935'], domain: nil,
          status: status, match_score: percentage, name_similarity: percentage
        )
      end

      result = matcher.match(place, [build.call('11444777000161', 0.70, 'ATIVA'), build.call('11222333000181', 0.66, 'INATIVA')]).to_h

      expect(result).to include(decision: :accept, accepted_cnpj: '11444777000161')
    end
  end
end
