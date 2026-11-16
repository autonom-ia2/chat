require 'rails_helper'

# E7 (#2900) — a carteira da corretora no conector de mentira: o mesmo formato do transporte real (snake_case), dados
# fictícios e coerentes, e os casos que a busca precisa saber tratar (inclusive os avisos do pedido, E7.5). E o
# transporte real manda as quatro operações para os caminhos do adapter, com o corpo em camelCase.
RSpec.describe Autonomia::Insurance::Connector::Mock::CarteiraDaCorretora, :aggregate_failures do
  let(:mock) { Autonomia::Insurance::Connector::Mock.new }
  let(:sessao) { { 'token' => 'viva' } }

  it 'o pedido da primeira busca traz os avisos com evidência; o da busca de todo dia, a lista vazia' do
    primeira = mock.portfolio_sync_start(provider: 'agger', session: sessao, desde: '2023-11-01', ate: '2026-11-01')
    expect(primeira).to include('status' => 'buscando')
    expect(primeira['por_seguradora'].pluck('situacao')).to eq(%w[pede_login sem_login])
    expect(primeira['por_seguradora'].last['nome']).to be_nil

    diaria = mock.portfolio_sync_start(provider: 'agger', session: sessao, desde: '2026-10-02', ate: '2026-11-01')
    expect(diaria['por_seguradora']).to eq([])
  end

  it 'o robô demora (só a busca de antes pergunta), e o período de mais de 37 meses é recusado, como no adapter' do
    freeze_time
    pedido = mock.portfolio_sync_start(provider: 'agger', session: sessao, desde: '2026-10-02', ate: '2026-11-01')
    andamento = -> { mock.portfolio_sync_status(provider: 'agger', session: sessao, sync_id: pedido['sync_id']) }
    expect(andamento.call['status']).to eq('buscando')
    travel(described_class::BUSCANDO_POR)
    expect(andamento.call['status']).to eq('pronta')
    expect(andamento.call['por_seguradora'].pluck('situacao')).not_to include('sem_login')

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

  it 'o transporte real devolve os avisos do pedido, e o pedido sem eles (o adapter de antes) continua igual' do
    allow(Aws::InstanceProfileCredentials).to receive(:new).and_return(Aws::Credentials.new('AKIAEXEMPLO', 'segredo-de-assinatura'))
    resposta = ->(corpo) { { status: 200, body: { 'statusCode' => 200, 'body' => corpo.to_json }.to_json } }
    aviso = { codigo: '903', nome: 'Seguradora Sol (exemplo)', situacao: 'pede_login' }
    stub_request(:post, 'https://lambda.us-east-1.amazonaws.com/2015-03-31/functions/adapters-test/invocations')
      .to_return(resposta.call(syncId: 's-1', status: 'buscando', porSeguradora: [aviso]), resposta.call(syncId: 's-2', status: 'buscando'))

    with_modified_env(INSURANCE_CONNECTOR_FUNCTION: 'adapters-test', AWS_REGION: 'us-east-1') do
      http = Autonomia::Insurance::Connector::Http.new
      expect(http.portfolio_sync_start(provider: 'agger', session: sessao, desde: '2024-01-01', ate: '2026-11-01'))
        .to eq('sync_id' => 's-1', 'status' => 'buscando',
               'por_seguradora' => [{ 'codigo' => '903', 'nome' => 'Seguradora Sol (exemplo)', 'situacao' => 'pede_login' }])
      expect(http.portfolio_sync_start(provider: 'agger', session: sessao, desde: '2024-01-01', ate: '2026-11-01'))
        .to eq('sync_id' => 's-2', 'status' => 'buscando')
    end
  end
end
