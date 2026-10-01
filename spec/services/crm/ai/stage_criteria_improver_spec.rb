require 'rails_helper'

RSpec.describe Crm::Ai::StageCriteriaImprover do
  let(:account) { instance_double(Account) }
  let(:pipeline) { instance_double(Crm::Pipeline, account: account, name: 'Funil de teste') }
  let(:stages) do
    [
      { 'name' => 'Novo', 'description' => 'Primeiro contato, antes da qualificação.' },
      { 'name' => 'Proposta', 'description' => 'Oferta apresentada; cliente está avaliando.' }
    ]
  end
  let(:credential) { { api_key: 'synthetic-test-key', source: :hook } }
  let(:resolver) { instance_double(Crm::Ai::CredentialResolver, resolve: credential) }
  let(:client) { instance_double(Crm::Ai::ResponsesClient) }

  it 'uses the selected stage and unsaved context without changing either stage' do
    original = stages.deep_dup
    suggestion = { 'description' => 'O cliente recebeu a oferta e está avaliando as condições.', 'note' => '' }
    allow(Crm::Ai::CredentialResolver).to receive(:new).with(account: account).and_return(resolver)
    allow(Crm::Ai::ResponsesClient).to receive(:new)
      .with(credential: credential, feature: 'classify', account: account, pipeline: pipeline).and_return(client)
    expect(client).to receive(:create) do |request|
      expect(request[:model]).to eq('gpt-6-luna')
      expect(request[:reasoning_effort]).to eq('high')
      expect(request[:schema]).to eq(described_class::SCHEMA)
      expect(JSON.parse(request[:input])).to eq(
        'pipeline_name' => 'Funil de teste', 'stages' => original, 'target_index' => 1, 'language' => 'pt_BR'
      )
      { text: suggestion.to_json }
    end

    result = described_class.new(pipeline: pipeline, stages: stages, stage_index: 1, language: 'pt_BR').perform

    expect(result).to eq(suggestion)
    expect(stages).to eq(original)
  end

  it 'accepts a blank target description for drafting from its name and context' do
    stages.last['description'] = ''

    expect(described_class.valid_input?('stages' => stages, 'stage_index' => 1)).to be(true)
  end

  it 'rejects an index outside the supplied stages' do
    expect(described_class.valid_input?('stages' => stages, 'stage_index' => 2)).to be(false)
  end

  it 'rejects string indices instead of choosing a different target by coercion' do
    expect(described_class.valid_input?('stages' => stages, 'stage_index' => '1')).to be(false)
  end
end
