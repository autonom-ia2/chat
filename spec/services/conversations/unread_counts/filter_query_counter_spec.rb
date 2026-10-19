require 'rails_helper'

RSpec.describe Conversations::UnreadCounts::FilterQueryCounter do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }

  before { create(:inbox_member, user: agent, inbox: inbox) }

  describe '#base_relation' do
    it 'applies the planner hint to permission scoping only for label filters' do
      label_query = { payload: [{ attribute_key: 'labels', filter_operator: 'equal_to', values: ['support'], query_operator: nil }] }
      status_query = { payload: [{ attribute_key: 'status', filter_operator: 'equal_to', values: ['open'], query_operator: nil }] }

      expect(described_class.new(account: account, user: agent, query: label_query).base_relation.to_sql)
        .to include('conversations.inbox_id + 0')
      expect(described_class.new(account: account, user: agent, query: status_query).base_relation.to_sql)
        .not_to include('inbox_id + 0')
    end

    # #1800: o número da pasta de quem só lê conta o que a lista dela mostra.
    it 'counts the unread conversations of the inbox for a role that only reads conversations' do
      role = CustomRole.create!(account: account, name: 'Leitura', permissions: %w[conversation_view])
      agent.account_users.find_by(account: account).update!(custom_role: role)
      conversation = create(:conversation, account: account, inbox: inbox, status: :open, agent_last_seen_at: 1.hour.ago,
                                           assignee: create(:user, account: account))
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming)
      query = { payload: [{ attribute_key: 'status', filter_operator: 'equal_to', values: ['open'], query_operator: nil }] }
      count = -> { described_class.new(account: account, user: agent, query: query).base_relation.count }

      expect(count.call).to eq(1)

      role.update!(permissions: %w[crm_view])
      expect(count.call).to eq(0)
    end
  end
end
