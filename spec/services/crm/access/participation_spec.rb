require 'rails_helper'

# Participante sempre vê (#1148). Quem tem acesso restrito na caixa não se dá esse passe (autoadição, automenção), e
# atribuição não é passe vitalício: ao reatribuir, quem saiu deixa de ser participante. Sem restrição, nada muda.
RSpec.describe 'Acesso por funil e participação' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:restricted) { create(:user, account: account, role: :agent) }
  let(:free_agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  before do
    [restricted, free_agent].each { |user| create(:inbox_member, inbox: inbox, user: user) }
    Crm::InboxAgentAccess.create!(account: account, inbox: inbox, user: restricted, all_pipelines: false, triage: true)
  end

  def assignee_event(changes)
    Events::Base.new(:'assignee.changed', Time.zone.now, conversation: conversation.reload, changed_attributes: changes)
  end

  describe ParticipationListener do
    it 'ao reatribuir, quem tem acesso restrito deixa de ser participante' do
      conversation.update!(assignee: restricted)
      described_class.instance.assignee_changed(assignee_event({ 'assignee_id' => [nil, restricted.id] }))
      expect(conversation.conversation_participants.where(user: restricted)).to exist

      conversation.update!(assignee: free_agent)
      described_class.instance.assignee_changed(assignee_event({ 'assignee_id' => [restricted.id, free_agent.id] }))

      expect(conversation.conversation_participants.where(user: restricted)).not_to exist
      expect(conversation.conversation_participants.where(user: free_agent)).to exist
    end

    it 'sem acesso restrito, quem foi atribuído segue participante como hoje' do
      conversation.update!(assignee: free_agent)
      described_class.instance.assignee_changed(assignee_event({ 'assignee_id' => [nil, free_agent.id] }))
      conversation.update!(assignee: restricted)
      described_class.instance.assignee_changed(assignee_event({ 'assignee_id' => [free_agent.id, restricted.id] }))

      expect(conversation.conversation_participants.where(user: free_agent)).to exist
    end
  end

  describe Messages::MentionService do
    def note_from(sender, mentioned)
      create(:message, account: account, inbox: inbox, conversation: conversation, private: true, sender: sender,
                       content: "oi (mention://user/#{mentioned.id}/#{mentioned.name})")
    end

    it 'quem tem acesso restrito não vira participante se mencionando' do
      described_class.new(message: note_from(restricted, restricted)).perform

      expect(conversation.conversation_participants.where(user: restricted)).not_to exist
    end

    it 'mencionado por outra pessoa, vira participante' do
      described_class.new(message: note_from(free_agent, restricted)).perform

      expect(conversation.conversation_participants.where(user: restricted)).to exist
    end
  end

  describe 'API de participantes', type: :request do
    def add(user, ids)
      post api_v1_account_conversation_participants_url(account_id: account.id, conversation_id: conversation.display_id),
           params: { user_ids: ids }, headers: user.create_new_auth_token, as: :json
    end

    it 'quem tem acesso restrito não se adiciona' do
      conversation.update!(assignee: restricted)

      add(restricted, [restricted.id])

      expect(response).to have_http_status(:forbidden)
      expect(conversation.conversation_participants.where(user: restricted)).not_to exist
    end

    it 'outra pessoa pode adicionar quem tem acesso restrito' do
      add(free_agent, [restricted.id])

      expect(response).to have_http_status(:success)
      expect(conversation.conversation_participants.where(user: restricted)).to exist
    end

    it 'sem acesso restrito, a pessoa se adiciona como hoje' do
      add(free_agent, [free_agent.id])

      expect(response).to have_http_status(:success)
    end
  end

  describe Crm::Ai::HandoffInviter do
    it 'não convida (nem dá participação a) quem o funil esconde' do
      Crm::InboxAgentAccess.find_by(user: restricted).update!(triage: false)
      result = described_class.new(conversation: conversation, agent: restricted).perform

      expect(result).to be(false)
      expect(conversation.conversation_participants.where(user: restricted)).not_to exist
    end

    it 'convida quem pode ver a conversa' do
      allow(NotificationBuilder).to receive(:new).and_return(instance_double(NotificationBuilder, perform: true))

      expect(described_class.new(conversation: conversation, agent: free_agent).perform).to be(true)
    end
  end

  describe 'casos de borda' do
    it 'administrador com linha de acesso se adiciona e não perde participação ao reatribuir' do
      Crm::InboxAgentAccess.create!(account: account, inbox: inbox, user: admin, all_pipelines: false, triage: false)

      expect(Crm::Access::ConversationScope.new(user: admin, account: account).restricted_in?(inbox.id)).to be(false)
    end

    it 'evento sem changed_attributes (atribuição V2) não remove ninguém' do
      ConversationParticipant.create!(account: account, conversation: conversation, user: restricted)
      conversation.update!(assignee: free_agent)

      ParticipationListener.instance.assignee_changed(
        Events::Base.new(:'assignee.changed', Time.zone.now, conversation: conversation.reload, user: free_agent)
      )

      expect(conversation.conversation_participants.where(user: restricted)).to exist
    end

    it 'reatribuir tira toda participação de quem tem acesso restrito, inclusive a dada por menção (atribuição não é passe)' do
      ConversationParticipant.create!(account: account, conversation: conversation, user: restricted)
      conversation.update!(assignee: restricted)
      conversation.update!(assignee: free_agent)
      changes = conversation.previous_changes

      ParticipationListener.instance.assignee_changed(
        Events::Base.new(:'assignee.changed', Time.zone.now, conversation: conversation.reload, changed_attributes: changes)
      )

      expect(conversation.conversation_participants.where(user: restricted)).not_to exist
    end
  end
end
