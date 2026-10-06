require 'rails_helper'

RSpec.describe Crm::MetaAds::StageTypeSuggester do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:pipeline) { account.crm_pipelines.create!(name: 'Viagem', created_by: user, status: :active) }
  let!(:first_stage) do
    account.crm_pipeline_stages.create!(pipeline: pipeline, name: 'Novo', position: 0, metadata: { 'ai_criteria' => 'Primeiro contato.' })
  end
  let!(:proposal) { account.crm_pipeline_stages.create!(pipeline: pipeline, name: 'Proposta', position: 1) }
  let!(:won) { account.crm_pipeline_stages.create!(pipeline: pipeline, name: 'Ganho', position: 2, is_won_stage: true) }
  let(:credential) { { api_key: 'synthetic-test-key', source: :hook } }
  let(:client) { instance_double(Crm::Ai::ResponsesClient) }

  before do
    resolver = instance_double(Crm::Ai::CredentialResolver, resolve: credential)
    allow(Crm::Ai::CredentialResolver).to receive(:new).with(account: account).and_return(resolver)
    allow(Crm::Ai::ResponsesClient).to receive(:new)
      .with(credential: credential, feature: 'classify', account: account, pipeline: pipeline).and_return(client)
  end

  it 'sends only progress stages, with the CRM criteria, and keeps only valid answers for this pipeline' do
    answer = { 'stages' => [
      { 'stage_id' => first_stage.id, 'type' => 'lead', 'reason' => 'O cliente começou a conversa.' },
      { 'stage_id' => proposal.id, 'type' => 'opportunity', 'reason' => 'Recebeu a proposta.' },
      { 'stage_id' => proposal.id, 'type' => 'negotiation', 'reason' => 'repetida' },
      { 'stage_id' => won.id, 'type' => 'negotiation', 'reason' => 'etapa de resultado' },
      { 'stage_id' => 999_999, 'type' => 'lead', 'reason' => 'de outro funil' }
    ] }
    expect(client).to receive(:create) do |request|
      expect(request[:schema]).to eq(described_class::SCHEMA)
      input = JSON.parse(request[:input])
      expect(input['stages']).to eq([
                                      { 'stage_id' => first_stage.id, 'position' => 0, 'name' => 'Novo', 'description' => 'Primeiro contato.' },
                                      { 'stage_id' => proposal.id, 'position' => 1, 'name' => 'Proposta', 'description' => '' }
                                    ])
      { text: answer.to_json }
    end

    result = described_class.new(pipeline: pipeline, language: 'pt_BR').perform

    expect(result[:suggestions]).to eq([
                                         { stage_id: first_stage.id, type: 'lead', reason: 'O cliente começou a conversa.' },
                                         { stage_id: proposal.id, type: 'opportunity', reason: 'Recebeu a proposta.' }
                                       ])
  end
end
