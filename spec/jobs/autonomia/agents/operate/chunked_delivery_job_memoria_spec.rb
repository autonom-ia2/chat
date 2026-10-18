require 'rails_helper'

# #1755: na entrega em pedaços, o `replied` grava os ids dos fatos de memória que viajaram no meta (só inteiros).
RSpec.describe Autonomia::Agents::Operate::ChunkedDeliveryJob do
  let(:account) { conta_da_fase2 }
  let(:conversation) { create(:conversation, account: account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Clara', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda.')
  end

  def replied_com(meta)
    described_class.new.send(:log_replied, agent, conversation, meta, nil)
    Autonomia::Agents::AgentEvent.where(conversation_id: conversation.id, event_type: :replied).last
  end

  it 'grava os ids da memória no metadata' do
    expect(replied_com('memoria_fact_ids' => [77, 812, '9', nil]).metadata).to eq('memoria_fact_ids' => [77, 812])
  end

  it 'sem memória no turno, o metadata fica vazio' do
    expect(replied_com('used_entry_ids' => [1]).metadata).to eq({})
  end
end
