require 'rails_helper'

# #1479 F2: na entrega em pedaços, o pedaço do pedido de localização grava a marca `autonomia_pedido_localizacao`, que
# vale mesmo quando o formato não sai; pedaço sem marca fica como antes.
RSpec.describe Autonomia::Agents::Operate::ChunkedDeliveryJob do
  let(:account) { conta_da_fase2 }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:agent) { criar_principal(account) }
  let(:agent_inbox) do
    Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: create(:agent_bot, account: account))
  end

  def postar(pedaco)
    described_class.new.send(:build_message!, conversation, agent_inbox, 99, 1, pedaco)
    conversation.messages.outgoing.last
  end

  it 'o pedaço do pedido leva a marca' do
    mensagem = postar('text' => 'Onde você está?', 'marca' => { 'autonomia_pedido_localizacao' => true })
    expect(mensagem.content_attributes).to include('autonomia_pedido_localizacao' => true)
  end

  it 'pedaço sem marca fica como antes' do
    mensagem = postar('text' => 'Oi.')
    expect(mensagem.content_attributes.keys).not_to include('autonomia_pedido_localizacao', 'marca')
  end
end
