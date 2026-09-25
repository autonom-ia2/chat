require 'rails_helper'

# A BUSCA DO SEGURADO NA FRONTEIRA (revisão da chat#718). O adapter escreve camelCase (`notFound`, `lookupFailed`,
# adapters#107) e a camada lê snake_case (`Http#normalize_keys`): é pela resposta crua da Lambda que se prova que o
# `lookup_failed` que a `BuscaDoSeguradoGuardada` lê chega, e que o `false` não some na tradução.
RSpec.describe Autonomia::Insurance::Connector::Http do
  let(:invoke_url) { 'https://lambda.us-east-1.amazonaws.com/2015-03-31/functions/adapters-test/invocations' }

  before do
    stub_const('ENV', ENV.to_h.merge('INSURANCE_CONNECTOR_FUNCTION' => 'adapters-test', 'AWS_REGION' => 'us-east-1'))
    allow(Aws::InstanceProfileCredentials).to receive(:new)
      .and_return(Aws::Credentials.new('AKIAEXEMPLO', 'segredo'))
  end

  def responder(corpo)
    stub_request(:post, invoke_url).to_return(
      status: 200, headers: { 'Content-Type' => 'application/json' },
      body: { 'statusCode' => 200, 'body' => corpo.to_json }.to_json
    )
  end

  def enriquecer
    described_class.new.quote_enrich(provider: 'agger', product: 'auto', input: { 'insured' => { 'document' => '1' } })
  end

  it 'a queda do fornecedor chega como lookup_failed verdadeiro, com os campos em not_found' do
    responder('input' => {}, 'notFound' => ['insured.name'], 'lookupFailed' => true)

    expect(enriquecer).to include('not_found' => ['insured.name'], 'lookup_failed' => true)
  end

  it 'a resposta sem o dado chega como lookup_failed falso, e o falso não some' do
    responder('input' => {}, 'notFound' => ['insured.name'], 'lookupFailed' => false)

    expect(enriquecer).to include('lookup_failed' => false)
  end
end
