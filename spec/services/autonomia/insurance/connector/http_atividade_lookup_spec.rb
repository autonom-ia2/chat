require 'rails_helper'

# A BUSCA DE ATIVIDADE NA FRONTEIRA (empresarial). Na conversa 7057 (24/09/2026) ela estourou os 10 s da conferência
# duas vezes: cada termo leva ~6 s no portal, e a Lia encaminhou o cliente sem cotar. Ela tem teto próprio, e a rota
# e o corpo são os que o adapter lê (`handler.ts`, `atividade/lookup`: `session`, `product`, `termos`).
RSpec.describe Autonomia::Insurance::Connector::Http do
  let(:invoke_url) { 'https://lambda.us-east-1.amazonaws.com/2015-03-31/functions/adapters-test/invocations' }
  let(:sessao) { { 'multicalculoToken' => 'm' } }
  let(:resposta) { { 'porTermo' => [{ 'termo' => 'escritorio', 'porSeguradora' => [] }] } }

  before do
    stub_const('ENV', ENV.to_h.merge('INSURANCE_CONNECTOR_FUNCTION' => 'adapters-test', 'AWS_REGION' => 'us-east-1'))
    allow(Aws::InstanceProfileCredentials).to receive(:new)
      .and_return(Aws::Credentials.new('AKIAEXEMPLO', 'segredo'))
    stub_request(:post, invoke_url).to_return(
      status: 200, headers: { 'Content-Type' => 'application/json' },
      body: { 'statusCode' => 200, 'body' => resposta.to_json }.to_json
    )
  end

  it 'chama a rota do adapter com sessao, produto e termos, no teto proprio da busca, maior que o da conferencia' do
    tempos = []
    # O timeout é posto num `Net::HTTP` que o próprio conector cria; não há costura para injetar.
    allow_any_instance_of(Net::HTTP).to receive(:read_timeout=) { |_, valor| tempos << valor } # rubocop:disable RSpec/AnyInstance

    lido = described_class.new.atividade_lookup(provider: 'agger', session: sessao, product: 'empresarial',
                                                termos: %w[escritorio contabilidade])

    # O conector entrega snake_case, como em toda a camada (`Http#normalize_keys`): é o que a ferramenta lê. Em 24/09 a
    # ferramenta e o mock liam camelCase, e a busca real daria "nenhuma seguradora tem opção".
    expect(lido).to eq('por_termo' => [{ 'termo' => 'escritorio', 'por_seguradora' => [] }])
    expect(WebMock).to(have_requested(:post, invoke_url).with do |req|
      evento = JSON.parse(req.body)
      evento['rawPath'] == '/v1/agger/atividade/lookup' &&
        JSON.parse(evento['body']) == { 'session' => sessao, 'product' => 'empresarial', 'termos' => %w[escritorio contabilidade] }
    end)
    expect(tempos).to eq([described_class::BUSCA_DE_ATIVIDADE_TIMEOUT])
    expect(described_class::BUSCA_DE_ATIVIDADE_TIMEOUT).to be > described_class::CONFERENCIA_TIMEOUT
  end
end
