require 'rails_helper'

# #1918: mandar o lead para o funil é escolher a etapa. A IA de etapa respeita essa escolha por um tempo
# (Crm::Ai::Evaluator::RESPEITO_AO_MOVIMENTO).
RSpec.describe Autonomia::Prospecting::CrmCardConverter do
  let(:account) { create(:account) }
  let(:user) { create(:user, :administrator, account: account) }
  let(:pipeline) { create_crm_pipeline(account: account, user: user).first }
  let(:stage) { pipeline.stages.first }
  let(:lead) do
    Autonomia::Prospecting::Lead.create!(account: account, provider: 'mock', provider_place_id: 'mock-place-1', name: 'Alpha Restaurante')
  end

  before { allow(Crm::Config).to receive(:enabled?).and_return(true) }

  it 'registra na linha do tempo que a pessoa escolheu a etapa' do
    result = described_class.new(lead: lead, user: user, pipeline_id: pipeline.id, stage_id: stage.id).perform

    expect(Crm::Activity.where(card: result.card, event_type: 'create').sole.payload).to include('etapa_escolhida' => true)
  end
end
