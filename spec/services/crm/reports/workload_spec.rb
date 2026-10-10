require 'rails_helper'

RSpec.describe Crm::Reports::Workload do
  let(:account) { create(:account) }
  let(:attendant) { create(:user, account: account, role: :agent, name: 'Atendente') }
  let(:seller) { create(:user, account: account, role: :agent, name: 'Vendedora') }
  let(:claims) { create(:user, account: account, role: :agent, name: 'Sinistros') }
  let(:inbox) { create_crm_inbox(account: account, members: [attendant, seller, claims]) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: attendant) }
  let(:conversation) do
    create_crm_conversation(account: account, inbox: inbox, contact: create(:contact, account: account), assignee: attendant)
  end

  def create_card(owner:, status: :open)
    pipeline, stage = pipeline_and_stage
    card = account.crm_cards.create!(
      pipeline: pipeline, stage: stage, primary_conversation: conversation, contact: conversation.contact,
      inbox: inbox, owner: owner, title: "Assunto #{SecureRandom.hex(3)}", currency: 'BRL'
    )
    card.update!(status: status) unless status == :open
    card
  end

  def workload
    described_class.new(account: account, params: { pipeline_id: pipeline_and_stage.first.id }).perform[:responsibles]
  end

  it 'counts each open card for its own owner, not for the conversation assignee' do
    create_card(owner: seller)
    create_card(owner: seller)
    create_card(owner: claims)
    create_card(owner: seller, status: :won)

    expect(workload).to contain_exactly(
      { key: "agent:#{seller.id}", type: 'agent', name: 'Vendedora', count: 2 },
      { key: "agent:#{claims.id}", type: 'agent', name: 'Sinistros', count: 1 }
    )
  end

  it 'leaves a card without owner out of the conversation assignee workload' do
    create_card(owner: nil)

    expect(workload).to eq([{ key: 'none', type: 'none', name: nil, count: 1 }])
  end

  it 'gives a card without owner to the inbox bot when one answers the inbox' do
    bot = create(:agent_bot, account: account, name: 'Bot da caixa')
    AgentBotInbox.create!(inbox: inbox, agent_bot: bot, status: :active)
    create_card(owner: nil)

    expect(workload).to eq([{ key: "bot:#{bot.id}", type: 'bot', name: 'Bot da caixa', count: 1 }])
  end
end
