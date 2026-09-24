require 'rails_helper'

RSpec.describe Crm::Ai::HandoffExecutor do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:inbox) { create_crm_inbox(account: account, members: [agent]) }
  let(:conversation) { create_crm_conversation(account: account, inbox: inbox, contact: contact) }

  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true' do
      example.run
    end
  end

  before do
    allow(Rails.configuration.dispatcher).to receive(:dispatch)
    allow(OnlineStatusTracker).to receive(:get_available_users).with(account.id).and_return({})
    allow(Crm::Ai::HandoffInviter).to receive(:new).and_return(instance_double(Crm::Ai::HandoffInviter, perform: true))
  end

  def build_card(ai_meta)
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    stage.update!(metadata: { 'ai_handoff' => { 'enabled' => true, 'handoff_mode' => 'r3_invite' } })
    account.crm_cards.create!(
      pipeline: pipeline,
      stage: stage,
      inbox: inbox,
      contact: contact,
      primary_conversation: conversation,
      title: 'Lead cooldown',
      metadata: { 'ai' => ai_meta }
    )
  end

  def perform(card)
    described_class.new(card: card, handoff: { intent: 'transferir', reason: 'cliente pediu humano' }).perform
  end

  it 'waives the cooldown when the last cycle was picked up and the conversation was released' do
    cycle = {
      'cycle_id' => 1, 'invited_at' => 30.minutes.ago.iso8601,
      'picked_up_at' => 20.minutes.ago.iso8601, 'picked_up_by' => admin.id,
      'invited_agent_id' => agent.id
    }
    card = build_card(
      'last_handoff_at' => 30.minutes.ago.iso8601,
      'handoff' => cycle,
      'handoffs' => [cycle]
    )

    result = perform(card)

    expect(result.status).to eq(:invited)
    cycles = card.reload.metadata.dig('ai', 'handoffs')
    expect(cycles.length).to eq(2)
    expect(cycles.last['picked_up_at']).to be_nil
  end

  it 'keeps the cooldown while the last cycle is still open (pending invite)' do
    cycle = {
      'cycle_id' => 1, 'invited_at' => 30.minutes.ago.iso8601,
      'invited_agent_id' => agent.id
    }
    card = build_card(
      'last_handoff_at' => 30.minutes.ago.iso8601,
      'handoff' => cycle,
      'handoffs' => [cycle]
    )

    result = perform(card)

    expect(result.status).to eq(:skipped)
    expect(result.error).to eq('cooldown')
  end

  it 'keeps the cooldown for an escalated cycle' do
    cycle = {
      'cycle_id' => 1, 'invited_at' => 2.hours.ago.iso8601,
      'escalated_at' => 30.minutes.ago.iso8601, 'escalated_to' => admin.id,
      'invited_agent_id' => agent.id
    }
    card = build_card(
      'last_handoff_at' => 2.hours.ago.iso8601,
      'handoff' => cycle,
      'handoffs' => [cycle]
    )

    result = perform(card)

    expect(result.status).to eq(:skipped)
    expect(result.error).to eq('cooldown')
  end
end
