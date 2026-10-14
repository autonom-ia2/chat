require 'rails_helper'

# chat#1505: a gaveta "Nova conversa" continua a conversa que o builder ou o recebimento escolheriam: no mesmo
# contact_inbox (source_id), pela regra da caixa, e só se a pessoa pode ver a conversa.
describe NovaConversa::ConversaParaContinuar do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create_crm_inbox(account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:source_id) { 'origem-1' }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: source_id) }

  def context_for(user)
    { user: user, account: account, account_user: AccountUser.find_by(account: account, user: user) }
  end

  def conversation_with(status, target_contact_inbox: contact_inbox)
    create(:conversation, account: account, inbox: target_contact_inbox.inbox, contact: target_contact_inbox.contact,
                          contact_inbox: target_contact_inbox, status: status)
  end

  def service(user = admin, source: source_id)
    described_class.new(inbox: inbox, contact: contact, source_id: source, user_context: context_for(user))
  end

  context 'when the inbox reopens the same conversation' do
    before { inbox.update!(lock_to_single_conversation: true) }

    it 'returns the latest conversation even when it is resolved' do
      conversation_with(:open)
      resolved = conversation_with(:resolved)

      expect(service.conversation).to eq(resolved)
      expect(service.payload).to eq(
        id: resolved.id, display_id: resolved.display_id, status: 'resolved',
        last_activity_at: resolved.last_activity_at.to_i, locked: true, visible: true
      )
    end
  end

  context 'when the inbox creates new conversations' do
    it 'ignores resolved conversations' do
      conversation_with(:resolved)

      expect(service.conversation).to be_nil
      expect(service.payload).to be_nil
    end

    it 'returns the most recent conversation that is not resolved' do
      conversation_with(:pending)
      latest_open = conversation_with(:open)
      conversation_with(:resolved)

      expect(service.conversation).to eq(latest_open)
    end

    it 'counts snoozed conversations as open' do
      snoozed = conversation_with(:snoozed)

      expect(service.conversation).to eq(snoozed)
    end

    it 'does not count conversations from another inbox or another contact' do
      other_inbox = create(:contact_inbox, contact: contact, inbox: create_crm_inbox(account: account, name: 'Outra'))
      other_contact = create(:contact_inbox, contact: create(:contact, account: account), inbox: inbox, source_id: 'outro')
      conversation_with(:open, target_contact_inbox: other_inbox)
      conversation_with(:open, target_contact_inbox: other_contact)

      expect(service.conversation).to be_nil
    end

    it 'only looks at the contact inbox the drawer will use (same source id)' do
      other_identity = create(:contact_inbox, contact: contact, inbox: inbox, source_id: 'origem-2')
      conversation_with(:open, target_contact_inbox: other_identity)
      mine = conversation_with(:pending)

      expect(service.conversation).to eq(mine)
      expect(service(source: 'origem-2').conversation).to eq(other_identity.conversations.last)
      expect(service(source: 'sem-conversa').conversation).to be_nil
    end
  end

  context 'when the agent cannot see the conversation (pipeline access)' do
    let(:agent) { create_crm_agent(account: account, name: 'Vendas').first }
    let(:pipeline) { create_crm_pipeline(account: account, user: admin, name: 'Vendas').first }

    before do
      inbox.add_members([agent.id])
      access = Crm::InboxAgentAccess.create!(account: account, inbox: inbox, user: agent, all_pipelines: false,
                                             triage: false, only_own: false)
      access.agent_pipelines.create!(account: account, pipeline: pipeline)
      conversation_with(:open)
    end

    it 'offers nothing when the inbox creates new conversations' do
      expect(service(agent).payload).to be_nil
      expect(service(admin).payload).to include(visible: true)
    end

    it 'warns without number or status when the inbox reopens the same conversation' do
      inbox.update!(lock_to_single_conversation: true)

      expect(service(agent).payload).to eq(
        id: nil, display_id: nil, status: nil, last_activity_at: nil, locked: true, visible: false
      )
    end
  end
end
