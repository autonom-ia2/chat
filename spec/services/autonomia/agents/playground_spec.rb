require 'rails_helper'

# #1367 (alavanca 0): o Testar é medido à parte do atendimento. Mesmo Answerer, outro rótulo de uso.
RSpec.describe Autonomia::Agents::Playground do
  let(:agent) { instance_double(Autonomia::Agents::Agent) }
  let(:answerer) { instance_double(Autonomia::Agents::Answerer, answer: :resultado) }

  before { allow(Autonomia::Agents::Answerer).to receive(:new).and_return(answerer) }

  it 'labels the usage as agente_teste, apart from the customer replies' do
    result = described_class.new(agent: agent, message: 'Oi', history: [], images: []).run

    expect(result).to eq(:resultado)
    expect(Autonomia::Agents::Answerer).to have_received(:new).with(
      hash_including(agent: agent, query: 'Oi', feature: 'agente_teste')
    )
  end
end
