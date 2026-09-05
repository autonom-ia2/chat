require 'rails_helper'

# O teste que faltava na casa toda: o payload aqui é LITERAL, capturado por invocação direta do
# Lambda de produção em 05/09/2026 10:42 UTC. Não é um payload que eu escrevi supondo o formato.
#
# Essa distinção não é acadêmica. O `Connector::Mock`, o `counting_connector` do spec de sessão e o
# `connector_answering` do spec de sync foram TODOS escritos reproduzindo a suposição de que o
# adapter devolvia snake_case. Três lugares verdes, nenhum tocando o formato real — e o resultado
# foi a sessão única nunca reusar nada em produção, com a tela acusando "credencial recusada" de
# uma credencial válida.
#
# Quando o contrato do adapter mudar, é para este arquivo que se volta: trocar o payload por outro
# capturado de verdade, e ver o que quebra.
RSpec.describe Autonomia::Insurance::Connector::Http do
  let(:invoke_url) { 'https://lambda.us-east-1.amazonaws.com/2015-03-31/functions/adapters-test/invocations' }

  before do
    stub_const('ENV', ENV.to_h.merge('INSURANCE_CONNECTOR_FUNCTION' => 'adapters-test', 'AWS_REGION' => 'us-east-1'))
    allow(Aws::InstanceProfileCredentials).to receive(:new)
      .and_return(Aws::Credentials.new('AKIAEXEMPLO', 'segredo'))
  end

  it 'traduz o payload que o Lambda de produção realmente devolveu' do
    # Arrange — resposta literal do adapter, com `checkedAt` em camelCase
    real = '{"platform":"agger","status":"auth_required","checkedAt":"2026-09-05T10:42:38.372Z",' \
           '"reason":"auth_required: GET https://api-prod.aggilizador.com.br/cfg/corretora -> 403"}'
    stub_request(:post, invoke_url).to_return(
      status: 200, headers: { 'Content-Type' => 'application/json' },
      body: { 'statusCode' => 200, 'body' => real }.to_json
    )

    # Act
    payload = described_class.new.connection_status(provider: 'agger',
                                                    session: { 'multicalculoToken' => 'x' })

    # Assert — o Rails recebe snake_case, e o camelCase não sobrevive à fronteira
    expect(payload['checked_at']).to eq('2026-09-05T10:42:38.372Z')
    expect(payload.keys).not_to include('checkedAt')
    expect(payload['status']).to eq('auth_required')
    expect(payload['reason']).to include('403')
  end
end
