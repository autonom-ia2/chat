require 'rails_helper'

# A CAUSA DA FALHA, para o log e para a decisão.
#
# Em 20/09/2026 uma cotação real morreu com `motivo=unavailable` no log e mais nada. O adapter não
# tinha registrado erro nenhum no mesmo minuto, e não havia como saber se a invocação foi recusada,
# se a resposta veio ilegível ou se o handler explodiu — três coisas muito diferentes, e uma delas
# significa que o portal nem foi tocado. Um dia de investigação para descobrir que a informação
# existia e era descartada na borda.
RSpec.describe Autonomia::Insurance::Connector::Http do
  let(:invoke_url) { 'https://lambda.us-east-1.amazonaws.com/2015-03-31/functions/adapters-test/invocations' }
  let(:with_session) { { provider: 'agger', session: { 'multicalculoToken' => 'multi' } } }

  before do
    stub_const('ENV', ENV.to_h.merge('INSURANCE_CONNECTOR_FUNCTION' => 'adapters-test', 'AWS_REGION' => 'us-east-1'))
    allow(Aws::InstanceProfileCredentials).to receive(:new)
      .and_return(Aws::Credentials.new('AKIAEXEMPLO', 'segredo-de-assinatura'))
  end

  def erro_de(outer_status: 200, outer_body: nil, inner_status: nil, inner_body: nil)
    body = outer_body || { 'statusCode' => inner_status, 'body' => inner_body }.to_json
    stub_request(:post, invoke_url).to_return(status: outer_status, body: body,
                                              headers: { 'Content-Type' => 'application/json' })
    described_class.new.quote_start(**with_session, product: 'auto', input: {})
  rescue Autonomia::Insurance::Connector::Error => e
    e
  end

  it 'a invocação recusada diz que o adapter não chegou a rodar' do
    # Arrange / Act — throttle, permissão, 5xx do próprio serviço de invocação
    erro = erro_de(outer_status: 429, outer_body: '{"message":"Rate exceeded"}')

    # Assert — é o que separa "não fez" de "pode ter feito"
    expect(erro.causa).to eq(:invoke_recusado)
    expect(erro).to be_nao_chegou_a_rodar
  end

  it 'o handler que explodiu não é a mesma coisa, e pode ter cotado' do
    # Arrange / Act
    erro = erro_de(outer_body: { 'errorType' => 'Runtime.ExitError' }.to_json)

    # Assert
    expect(erro.causa).to eq(:handler_quebrou)
    expect(erro).not_to be_nao_chegou_a_rodar
  end

  it 'resposta que não se lê também é incerteza' do
    # Arrange / Act
    erro = erro_de(outer_body: 'isto não é json')

    # Assert
    expect(erro.causa).to eq(:resposta_ilegivel)
    expect(erro).not_to be_nao_chegou_a_rodar
  end

  it 'status de erro do handler é recusa de negócio, e chega etiquetada' do
    # Arrange / Act
    erro = erro_de(inner_status: 502, inner_body: { 'error' => { 'message' => 'portal fora' } }.to_json)

    # Assert
    expect(erro.causa).to eq(:status_do_handler)
    expect(erro.etiqueta).to eq('unavailable/status_do_handler')
  end

  it 'a etiqueta nunca carrega texto do portal nem credencial' do
    # Arrange / Act — o corpo traz uma mensagem do portal; ela pode ir para a resposta, nunca para
    # a etiqueta, que é o campo que vai para o log
    erro = erro_de(inner_status: 502, inner_body: { 'error' => { 'message' => 'token abc123 recusado' } }.to_json)

    # Assert
    expect(erro.etiqueta).not_to include('abc123')
    expect(erro.etiqueta).to eq('unavailable/status_do_handler')
  end
end
