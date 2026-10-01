require 'rails_helper'

RSpec.describe Crm::Conversations::Visibility do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent_and_membership) { create_crm_agent(account: account) }
  let(:agent) { agent_and_membership.first }
  let(:contact) { create(:contact, account: account) }
  let(:inboxes) do
    { normal: create_crm_inbox(account: account, members: [agent]),
      assigned_only: create_crm_inbox(account: account, members: [agent]),
      hidden: create_crm_inbox(account: account) }
  end
  let(:everyone) { create_crm_conversation(account: account, inbox: inboxes.fetch(:normal), contact: contact) }
  let(:assigned) { create_crm_conversation(account: account, inbox: inboxes.fetch(:assigned_only), contact: contact, assignee: agent) }
  let(:participating) { create_crm_conversation(account: account, inbox: inboxes.fetch(:assigned_only), contact: contact, assignee: admin) }
  let(:unassigned) { create_crm_conversation(account: account, inbox: inboxes.fetch(:assigned_only), contact: contact, assignee: admin) }
  let(:inaccessible) { create_crm_conversation(account: account, inbox: inboxes.fetch(:hidden), contact: contact) }
  let(:foreign) { create(:conversation) }
  let(:conversations) { [everyone, assigned, participating, unassigned, inaccessible, foreign] }
  let(:visibility) { described_class.new(account: account, user: agent, account_user: agent_and_membership.last) }

  before do
    account.crm_inbox_settings.create!(inbox: inboxes.fetch(:assigned_only), visibility_mode: :assigned_only)
    conversations
    participating.conversation_participants.create!(account: account, user: agent)
  end

  it 'matches the existing per-record predicate in SQL without expanding access or other accounts' do
    ids = conversations.select { |conversation| visibility.visible?(conversation) }.map(&:id)
    expect(ids).to contain_exactly(everyone.id, assigned.id, participating.id)
    expect(visibility.scope(Conversation.all).pluck(:id)).to match_array(ids)
  end

  it 'preserves an already narrower input relation' do
    scope = Conversation.where(id: [assigned.id, inaccessible.id, foreign.id])
    expect(visibility.scope(scope).pluck(:id)).to eq([assigned.id])
  end

  it 'keeps administrator access confined to the selected account' do
    checker = described_class.new(account: account, user: admin, account_user: admin.account_users.find_by!(account: account))
    expect(checker.scope(Conversation.all).pluck(:id)).to match_array(account.conversations.pluck(:id))
    expect(checker.scope(Conversation.all).pluck(:id)).not_to include(foreign.id)
  end

  it 'does not infer permissions from a missing user' do
    checker = described_class.new(account: account, user: nil, account_user: nil)
    expect(checker.scope(Conversation.all)).to be_empty
    expect(conversations.any? { |conversation| checker.visible?(conversation) }).to be(false)
  end

  it 'reflects revoked membership in the next request context' do
    expect(visibility.scope(Conversation.all).pluck(:id)).to include(everyone.id)
    inboxes.fetch(:normal).inbox_members.where(user_id: agent.id).destroy_all
    checker = described_class.new(account: account, user: agent.reload, account_user: agent_and_membership.last)
    expect(checker.scope(Conversation.all).pluck(:id)).not_to include(everyone.id)
    expect(checker.visible?(everyone)).to be(false)
  end

  it 'does not let participation bypass inbox membership' do
    inboxes.fetch(:hidden).add_members([agent.id])
    inaccessible.conversation_participants.create!(account: account, user: agent)
    inboxes.fetch(:hidden).inbox_members.where(user_id: agent.id).destroy_all
    expect(visibility.scope(Conversation.all).pluck(:id)).not_to include(inaccessible.id)
    expect(visibility.visible?(inaccessible)).to be(false)
  end
end
