require 'rails_helper'

# Porte de lib/services/research/company-owner/bigdatacorp-discovery.test.ts do Orth (#679).
RSpec.describe Autonomia::Prospecting::Research::BigDataCorpDiscovery do
  let(:client_error) { Autonomia::Prospecting::Research::BigDataCorpClient::Error }
  let(:calls) { [] }
  let(:responses) { [] }
  let(:client) do
    recorded = calls
    queue = responses
    Class.new do
      define_method(:search_companies) do |query:, limit:, datasets:|
        recorded << { Datasets: datasets, q: query, Limit: limit }
        response = queue.shift
        raise response if response.is_a?(Exception)

        response
      end
    end.new
  end
  let(:discovery) { described_class.new(client: client) }

  def fixture(name)
    JSON.parse(Rails.root.join('spec/fixtures/prospecting_bigdatacorp', name).read)
  end

  def response(payload, request_id = nil)
    Autonomia::Prospecting::Research::BigDataCorpClient::Response.new(
      payload: payload, metadata: { provider_attempts: 1, token_generations: 1, provider_request_id: request_id }
    )
  end

  def valid_empty_payload(query_id = 'sanitized-query-empty-1')
    { 'QueryId' => query_id, 'Status' => { 'basic_data' => [{ 'Code' => 0, 'Message' => 'OK' }] }, 'Result' => [] }
  end

  def discovery_error
    yield
    raise 'era esperado um erro'
  rescue described_class::Error => e
    e
  end

  it 'sempre manda o nome canônico, acrescenta o telefone só quando há e fixa Limit=3' do
    responses.push(response(valid_empty_payload), response(valid_empty_payload))

    discovery.discover(name: '  Empresa Exemplo  ', phone: '  +5511999999999  ')
    discovery.discover(name: 'Sem Telefone')

    expect(calls).to eq([
                          { Datasets: 'basic_data', q: 'name{Empresa Exemplo},phone{+5511999999999}', Limit: 3 },
                          { Datasets: 'basic_data', q: 'name{Sem Telefone}', Limit: 3 }
                        ])
  end

  it 'normaliza a fixture sanitizada do fornecedor sem passar de três candidatos' do
    responses.push(response(fixture('basic_data_official_success.json'), 'sanitized-query-success-1'))

    result = discovery.discover(name: 'Empresa Exemplo', phone: '+5511999999999')

    expect(result.candidates.map(&:to_h)).to eq([
                                                  {
                                                    cnpj: '12345678000199', name: 'Empresa Exemplo Ltda', trade_name: 'Empresa Exemplo',
                                                    status: 'ATIVA', is_headquarter: true, headquarter_state: 'SP',
                                                    match_keys: ['name{Emp**********lo},phone{********9999}'],
                                                    official_name_percentage: 98.5, trade_name_percentage: 100.0, provider_index: 0
                                                  },
                                                  {
                                                    cnpj: '98765432000188', name: 'Empresa Exemplo Interior Ltda',
                                                    trade_name: 'Empresa Exemplo Interior', status: 'BAIXADA', is_headquarter: false,
                                                    headquarter_state: 'SP', match_keys: ['name{Emp*********************or}'],
                                                    official_name_percentage: 87.0, trade_name_percentage: 91.25, provider_index: 1
                                                  }
                                                ])
    expect(result.provider_request_id).to eq('sanitized-query-success-1')
  end

  it 'normaliza o telefone pelo contrato de telefone antes de montar o q' do
    responses.push(response(valid_empty_payload))

    discovery.discover(name: 'Empresa Exemplo', phone: '(11) 99999-9999', region: 'BR')

    expect(calls.last[:q]).to eq('name{Empresa Exemplo},phone{+5511999999999}')
  end

  it 'limita a três candidatos uma resposta grande demais' do
    row = { 'MatchKeys' => 'name{Emp**********lo}',
            'BasicData' => { 'TaxIdNumber' => '12345678000199', 'OfficialName' => 'Empresa Exemplo Ltda', 'TaxIdStatus' => 'ATIVA' } }
    responses.push(response(valid_empty_payload('sanitized-query-oversized-1').merge('Result' => [row, row, row, row])))

    expect(discovery.discover(name: 'Empresa Exemplo').candidates.size).to eq(3)
  end

  it 'devolve lista vazia só para um resultado vazio válido' do
    responses.push(response(valid_empty_payload))

    expect(discovery.discover(name: 'Empresa Ausente').candidates).to eq([])
  end

  it 'separa erro semântico do fornecedor de resultado vazio' do
    responses.push(response(fixture('basic_data_semantic_error.json')))

    error = discovery_error { discovery.discover(name: 'Consulta Inválida') }

    expect(error).to have_attributes(code: 'BIGDATACORP_SEMANTIC_ERROR', provider_request_id: 'sanitized-query-semantic-1')
  end

  it 'trata Code diferente de zero em Status.basic_data com HTTP 200 como erro semântico' do
    responses.push(response(fixture('basic_data_official_status_error.json'), 'sanitized-query-error-1'))

    error = discovery_error { discovery.discover(name: 'Consulta Com Status') }

    expect(error).to have_attributes(code: 'BIGDATACORP_SEMANTIC_ERROR', provider_request_id: 'sanitized-query-error-1')
  end

  {
    'sem Status' => { 'QueryId' => 'sanitized-query-invalid-1', 'Result' => [] },
    'basic_data como objeto' => { 'QueryId' => 'sanitized-query-invalid-2', 'Status' => { 'basic_data' => { 'Code' => 0 } }, 'Result' => [] },
    'basic_data vazio' => { 'QueryId' => 'sanitized-query-invalid-3', 'Status' => { 'basic_data' => [] }, 'Result' => [] },
    'sem QueryId' => { 'Status' => { 'basic_data' => [{ 'Code' => 0 }] }, 'Result' => [] },
    'sem Code no status' => { 'QueryId' => 'sanitized-query-invalid-4', 'Status' => { 'basic_data' => [{ 'Message' => 'x' }] }, 'Result' => [] },
    'sem Result' => { 'QueryId' => 'sanitized-query-invalid-5', 'Status' => { 'basic_data' => [{ 'Code' => 0 }] } }
  }.each do |label, payload|
    it "recusa envelope oficial incompleto: #{label}" do
      responses.push(response(payload))

      error = discovery_error { discovery.discover(name: 'Envelope Incompleto') }

      expect(error).to have_attributes(code: 'BIGDATACORP_INVALID_PROVIDER_RESPONSE', provider_request_id: payload['QueryId'])
    end
  end

  basic = { 'TaxIdNumber' => '12345678000199', 'OfficialName' => 'Formato Não Oficial', 'TaxIdStatus' => 'ATIVA' }
  {
    'linha sem BasicData' => basic,
    'status com apelido não oficial' => { 'BasicData' => basic.except('TaxIdStatus').merge('Status' => 'ATIVA') },
    'MatchKeys como array' => { 'MatchKeys' => %w[name phone], 'BasicData' => basic },
    'sem MatchKeys' => { 'BasicData' => basic },
    'MatchKeys vazio' => { 'MatchKeys' => '   ', 'BasicData' => basic },
    'matchKeys minúsculo' => { 'matchKeys' => 'name{Emp***al}', 'BasicData' => basic }
  }.each do |label, row|
    it "recusa linha de resultado fora do formato oficial: #{label}" do
      responses.push(response(valid_empty_payload('sanitized-query-non-official-1').merge('Result' => [row])))

      error = discovery_error { discovery.discover(name: 'Formato Não Oficial') }

      expect(error).to have_attributes(code: 'BIGDATACORP_INVALID_PROVIDER_RESPONSE', provider_request_id: 'sanitized-query-non-official-1')
    end
  end

  it 'deixa o erro tipado do cliente passar sem trocar o código' do
    responses.push(client_error.new('BIGDATACORP_TIMEOUT', phase: :provider, provider_attempts: 1))

    expect { discovery.discover(name: 'Consulta Ambígua') }.to raise_error(client_error) { |error| expect(error.code).to eq('BIGDATACORP_TIMEOUT') }
  end

  it 'trata doc_finder sem documentos como zero candidatos, não como falha' do
    payload = { 'QueryId' => 'doc-finder-empty-1', 'Status' => { 'doc_finder' => [{ 'Code' => -100, 'Message' => 'no documents found' }] },
                'Result' => [] }
    responses.push(response(payload))

    expect(discovery.discover(name: 'Bar e Restaurante do Exemplo').candidates).to eq([])
  end

  it 'recusa entrada malformada ou insegura antes de chamar o fornecedor' do
    expect(discovery_error { discovery.discover(name: '   ') }.code).to eq('BIGDATACORP_INVALID_DISCOVERY_INPUT')

    responses.push(response(valid_empty_payload))
    discovery.discover(name: 'Empresa},phone{injetado')
    expect(calls.last[:q]).to eq('name{Empresa phone injetado}')

    [
      -> { discovery.discover(name: "Empresa#{0.chr}Controle") },
      -> { discovery.discover(name: 'N' * 201) },
      -> { discovery.discover(name: 'Telefone Longo', phone: "+#{'1' * 64}", region: 'BR') },
      -> { discovery.discover(name: 'Empresa Segura', phone: '{injetado},name{x}', region: 'BR') }
    ].each { |call| expect(discovery_error(&call).code).to eq('BIGDATACORP_INVALID_DISCOVERY_INPUT') }
    expect(calls.size).to eq(1)
  end
end
