require 'rails_helper'

RSpec.describe ConversationPolicy, type: :policy do
  subject { described_class }

  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:agent_account_user) { agent.account_users.find_by(account: account) }
  let(:context) { { user: agent, account: account, account_user: agent_account_user } }

  before do
    create(:inbox_member, user: agent, inbox: inbox)
  end

  permissions :show? do
    context 'when role grants conversation_unassigned_manage' do
      let(:custom_role) { create(:custom_role, account: account, permissions: ['conversation_unassigned_manage']) }

      before do
        agent_account_user.update!(role: :agent, custom_role: custom_role)
      end

      it 'allows access to conversations assigned to the agent' do
        conversation = create(:conversation, account: account, inbox: inbox, assignee: agent)

        expect(subject).to permit(context, conversation)
      end

      it 'denies access to conversations assigned to someone else' do
        other_agent = create(:user, account: account, role: :agent)
        conversation = create(:conversation, account: account, inbox: inbox, assignee: other_agent)

        expect(subject).not_to permit(context, conversation)
      end

      it 'denies access to conversations assigned to an agent bot' do
        conversation = create(:conversation, account: account, inbox: inbox, ai_assignee: create(:agent_bot, account: account))

        expect(subject).not_to permit(context, conversation)
      end

      it 'allows access to a conversation the bot handed off that waits for a person (#1377)' do
        conversation = create(:conversation, account: account, inbox: inbox, ai_assignee: create(:agent_bot, account: account))
        conversation.bot_handoff!

        expect(subject).to permit(context, conversation.reload)
      end
    end

    context 'when role grants conversation_participating_manage' do
      let(:custom_role) { create(:custom_role, account: account, permissions: ['conversation_participating_manage']) }

      before do
        agent_account_user.update!(role: :agent, custom_role: custom_role)
      end

      it 'allows access to conversations assigned to the agent' do
        conversation = create(:conversation, account: account, inbox: inbox, assignee: agent)

        expect(subject).to permit(context, conversation)
      end

      it 'allows access to conversations where the agent is a participant' do
        conversation = create(:conversation, account: account, inbox: inbox, assignee: nil)
        create(:conversation_participant, conversation: conversation, account: account, user: agent)

        expect(subject).to permit(context, conversation)
      end

      it 'denies access to unrelated conversations' do
        conversation = create(:conversation, account: account, inbox: inbox, assignee: nil)

        expect(subject).not_to permit(context, conversation)
      end
    end
  end

  # #1800: conversation_view lê sem operar. view? passa; show? (porta da escrita) não.
  context 'when role grants only conversation_view' do
    let(:custom_role) { create(:custom_role, account: account, permissions: ['conversation_view']) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: create(:user, account: account, role: :agent)) }

    before { agent_account_user.update!(role: :agent, custom_role: custom_role) }

    it 'reads but does not operate conversations of its inbox' do
      policy = described_class.new(context, conversation)

      expect(policy.view?).to be(true)
      expect(policy.show?).to be(false)
      expect(described_class.new(context, Conversation).create?).to be(false)
    end

    it 'does not read conversations of other inboxes' do
      outside = create(:conversation, account: account, inbox: create(:inbox, account: account))

      expect(described_class.new(context, outside).view?).to be(false)
    end
  end

  context 'when role grants only the trio' do
    let(:custom_role) { create(:custom_role, account: account, permissions: ['conversation_participating_manage']) }

    before { agent_account_user.update!(role: :agent, custom_role: custom_role) }

    it 'reads exactly what it operates' do
      mine = create(:conversation, account: account, inbox: inbox, assignee: agent)
      other = create(:conversation, account: account, inbox: inbox, assignee: nil)

      expect(described_class.new(context, mine)).to have_attributes(view?: true, show?: true, create?: true)
      expect(described_class.new(context, other)).to have_attributes(view?: false, show?: false)
    end
  end

  # O caminho do robô não depende de função: AgentBot passa em show? e view?, com conversation_view existindo na conta.
  it 'keeps letting the agent bot read and operate' do
    create(:custom_role, account: account, permissions: ['conversation_view'])
    bot = create(:agent_bot, account: account)
    conversation = create(:conversation, account: account, inbox: inbox)
    policy = described_class.new({ user: bot, account: account, account_user: nil }, conversation)

    expect(policy).to have_attributes(show?: true, view?: true)
  end
end
