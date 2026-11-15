require 'rails_helper'

# E7 (#2900) — a carteira da corretora no conector de mentira: o mesmo formato do transporte real (snake_case), dados
# fictícios e coerentes, e os casos que a busca precisa saber tratar (inclusive o período em fatias de um mês, E7.5). E o
# transporte real manda as quatro operações para os caminhos do adapter, com o corpo em camelCase.
RSpec.describe Autonomia::Insurance::Connector::Mock::CarteiraDaCorretora, :aggregate_failures do
  let(:mock) { Autonomia::Insurance::Connector::Mock.new }
  let(:sessao) { { 'token' => 'viva' } }

  it 'a busca demora: o período sai em fatias de um mês, e o pedido só termina depois da última' do
    freeze_time
    pedido = mock.portfolio_sync_start(provider: 'agger', session: sessao, desde: '2023-11-01', ate: '2026-11-01')
    expect(pedido).to include('status' => 'buscando')
    andamento = -> { mock.portfolio_sync_status(provider: 'agger', session: sessao, sync_id: pedido['sync_id']) }

    expect(andamento.call).to include('status' => 'buscando', 'fatias' => { 'pedidas' => 1, 'total' => 37 })
    travel(described_class::FATIA_POR * 10)
    expect(andamento.call).to include('status' => 'buscando', 'fatias' => { 'pedidas' => 11, 'total' => 37 })

    travel(described_class::FATIA_POR * 30)
    expect(andamento.call['status']).to eq('pronta')
    expect(andamento.call['fatias']).to eq('pedidas' => 37, 'total' => 37)
    expect(andamento.call['por_seguradora'].pluck('situacao')).to eq(%w[pronta pronta pede_login sem_login])
    expect(andamento.call['por_seguradora'].last['nome']).to be_nil
  end

  it 'a última semana é uma fatia só, e o período de mais de 37 meses é recusado, como no adapter' do
    freeze_time
    pedido = mock.portfolio_sync_start(provider: 'agger', session: sessao, desde: '2026-10-25', ate: '2026-11-01')
    expect(mock.portfolio_sync_status(provider: 'agger', session: sessao, sync_id: pedido['sync_id'])['fatias'])
      .to eq('pedidas' => 1, 'total' => 1)

    expect { mock.portfolio_sync_start(provider: 'agger', session: sessao, desde: '2023-09-30', ate: '2026-11-01') }
      .to raise_error(Autonomia::Insurance::Connector::Error) { |erro| expect(erro.kind).to eq(:validation) }
  end

  it 'a lista vem em duas páginas: um item sem referência, um endosso da mesma apólice e o que o adapter não leu' do
    sync_id = mock.portfolio_sync_start(provider: 'agger', session: sessao, desde: '2024-01-01', ate: '2026-11-01')['sync_id']
    primeira = mock.portfolio_policies(provider: 'agger', session: sessao, sync_id: sync_id)
    segunda = mock.portfolio_policies(provider: 'agger', session: sessao, sync_id: sync_id, cursor: primeira['proximo_cursor'])

    expect(primeira['itens'].pluck('ref')).to eq(['mock-ref-1', 'mock-ref-2', nil])
    expect(segunda['itens'].pluck('ref')).to eq(%w[mock-ref-1 mock-ref-4])
    expect(segunda['itens'].first['endosso']).to include('numero' => '1')
    expect(segunda['proximo_cursor']).to be_nil
    expect(primeira['itens'].size + segunda['itens'].size + segunda['ignorados']).to eq(segunda['total'])
  end

  it 'o documento devolve um endereço, e o período ou o pedido fora do formato são recusados' do
    expect(mock.portfolio_document(provider: 'agger', session: sessao, ref: 'mock-pdf-1')).to include('url')
    expect { mock.portfolio_sync_start(provider: 'agger', session: sessao, desde: '2026-11-01', ate: '2024-01-01') }
      .to raise_error(Autonomia::Insurance::Connector::Error) { |erro| expect(erro.kind).to eq(:validation) }
    expect { mock.portfolio_policies(provider: 'agger', session: sessao, sync_id: 'outro') }
      .to raise_error(Autonomia::Insurance::Connector::Error) { |erro| expect(erro.kind).to eq(:validation) }
  end

  it 'o transporte real chama os caminhos da carteira, com o corpo em camelCase' do
    http = Autonomia::Insurance::Connector::Http.new
    chamadas = []
    allow(http).to receive(:invoke) do |caminho, corpo|
      chamadas << [caminho, corpo]
      {}
    end

    http.portfolio_sync_start(provider: 'agger', session: sessao, desde: '2024-01-01', ate: '2026-11-01')
    http.portfolio_sync_status(provider: 'agger', session: sessao, sync_id: 's-1')
    http.portfolio_policies(provider: 'agger', session: sessao, sync_id: 's-1', cursor: 'c-2')
    http.portfolio_document(provider: 'agger', session: sessao, ref: 'r-1')

    expect(chamadas).to eq([
                             ['/v1/agger/portfolio/sync/start', { session: sessao, desde: '2024-01-01', ate: '2026-11-01' }],
                             ['/v1/agger/portfolio/sync/status', { session: sessao, syncId: 's-1' }],
                             ['/v1/agger/portfolio/policies', { session: sessao, syncId: 's-1', cursor: 'c-2' }],
                             ['/v1/agger/portfolio/document', { session: sessao, ref: 'r-1' }]
                           ])
  end

  it 'o transporte real devolve as fatias do andamento, e o andamento sem elas (o adapter de antes) continua igual' do
    allow(Aws::InstanceProfileCredentials).to receive(:new).and_return(Aws::Credentials.new('AKIAEXEMPLO', 'segredo-de-assinatura'))
    resposta = ->(corpo) { { status: 200, body: { 'statusCode' => 200, 'body' => corpo.to_json }.to_json } }
    stub_request(:post, 'https://lambda.us-east-1.amazonaws.com/2015-03-31/functions/adapters-test/invocations')
      .to_return(resposta.call(status: 'buscando', porSeguradora: [], fatias: { pedidas: 5, total: 37 }),
                 resposta.call(status: 'pronta', porSeguradora: []))

    with_modified_env(INSURANCE_CONNECTOR_FUNCTION: 'adapters-test', AWS_REGION: 'us-east-1') do
      http = Autonomia::Insurance::Connector::Http.new
      expect(http.portfolio_sync_status(provider: 'agger', session: sessao, sync_id: 's-1'))
        .to eq('status' => 'buscando', 'por_seguradora' => [], 'fatias' => { 'pedidas' => 5, 'total' => 37 })
      expect(http.portfolio_sync_status(provider: 'agger', session: sessao, sync_id: 's-1'))
        .to eq('status' => 'pronta', 'por_seguradora' => [])
    end
  end
end
