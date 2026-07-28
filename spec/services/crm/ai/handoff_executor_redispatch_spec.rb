require 'rails_helper'

# Caso real (conta 16, 2026-07-28): o handoff atribuiu, o operador DESATRIBUIU de proposito
# (devolveu ao bot), o gatilho aconteceu de novo 50min depois e nada foi transferido — o
# cooldown de 6h segurava. A dispensa ja existia, mas so no r3_invite, que grava ciclo.
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
    allow(OnlineStatusTracker).to receive(:get_available_users).with(account.id).and_return({ agent.id => 'online' })
    allow(Crm::Ai::HandoffInviter).to receive(:new).and_return(instance_double(Crm::Ai::HandoffInviter, perform: true))
  end

  def build_card(handoff_mode:, ai_meta:)
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    stage.update!(metadata: { 'ai_handoff' => { 'enabled' => true, 'handoff_mode' => handoff_mode } })
    account.crm_cards.create!(
      pipeline: pipeline, stage: stage, inbox: inbox, contact: contact,
      primary_conversation: conversation, title: 'Lead', metadata: { 'ai' => ai_meta }
    )
  end

  def perform(card)
    described_class.new(card: card, handoff: { intent: 'transferir', reason: 'gatilho atendido' }).perform
  end

  it 'reatribui no modo direto quando a conversa foi devolvida ao bot, ignorando o cooldown' do
    card = build_card(handoff_mode: 'r2_direct', ai_meta: { 'last_handoff_at' => 10.minutes.ago.iso8601 })

    result = perform(card)

    expect(result.status).to eq(:handed_off)
    expect(conversation.reload.assignee_id).to eq(agent.id)
  end

  it 'mantem o cooldown no modo convite, onde o ciclo e quem diz se foi resolvido' do
    card = build_card(handoff_mode: 'r3_invite', ai_meta: { 'last_handoff_at' => 10.minutes.ago.iso8601 })

    expect(perform(card).error).to eq('cooldown')
  end
end
