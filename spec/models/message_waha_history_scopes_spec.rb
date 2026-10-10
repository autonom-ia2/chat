require 'rails_helper'

# content_attributes is a `json` column written by `store ... coder: JSON`, so it usually holds a JSON string with the
# object inside. Rows written elsewhere can hold `""`, a bare object, NULL or a non-object scalar. None of them may
# break the account-wide unread count or report queries that use these scopes.
RSpec.describe Message do
  describe '.without_waha_history' do
    let(:conversation) { create(:conversation) }
    let!(:live) { create(:message, conversation: conversation, message_type: :incoming) }
    let!(:historical) do
      previous = Current.waha_history_import
      Current.waha_history_import = true
      create(:message, conversation: conversation, message_type: :incoming, content_attributes: { 'waha_history_import' => true })
    ensure
      Current.waha_history_import = previous
    end

    def write_raw_content_attributes(message, sql_value)
      Message.connection.execute("UPDATE messages SET content_attributes = #{sql_value} WHERE id = #{message.id}")
    end

    it 'excludes only messages imported from history' do
      expect(conversation.messages).to include(historical)
      expect(conversation.messages.without_waha_history).to contain_exactly(live)
      expect(conversation.messages.for_reporting).to contain_exactly(live)
    end

    {
      'an empty JSON string' => %q('""'::json),
      'a bare JSON object' => %q('{"waha_history_import": true}'::json),
      'NULL' => 'NULL',
      'a non-object JSON string' => %q('"waha_history_import"'::json)
    }.each do |shape, sql_value|
      it "keeps working when a row holds #{shape}" do
        odd = create(:message, conversation: conversation, message_type: :incoming)
        write_raw_content_attributes(odd, sql_value)

        expected = shape == 'a bare JSON object' ? [live] : [live, odd]
        expect(conversation.messages.without_waha_history).to match_array(expected)
        expect { conversation.messages.non_historical.to_a }.not_to raise_error
        expect { conversation.messages.pending_waha_outbound.to_a }.not_to raise_error
      end
    end
  end

  describe 'account-wide queries with an empty content_attributes row' do
    let(:account) { create(:account) }
    let(:inbox) { create(:inbox, account: account) }
    let(:agent) { create(:user, account: account, role: :agent) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :open) }

    before do
      incoming = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming)
      outgoing = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: agent)
      described_class.where(id: [incoming.id, outgoing.id]).update_all("content_attributes = '\"\"'::json") # rubocop:disable Rails/SkipsModelValidations
    end

    after { Conversations::UnreadCounts::Store.clear_account!(account.id) }

    it 'still builds the unread counts' do
      builder = Conversations::UnreadCounts::Builder.new(account)

      expect { builder.build_base! }.not_to raise_error
      expect(Conversations::UnreadCounts::Store.base_ready?(account.id)).to be(true)
    end

    it 'still counts outgoing messages in the v2 report' do
      params = { group_by: 'agent', since: 1.day.ago.to_i.to_s, until: 1.day.from_now.to_i.to_s }

      result = V2::Reports::OutgoingMessagesCountBuilder.new(account, params).build

      expect(result).to contain_exactly(hash_including(id: agent.id, outgoing_messages_count: 1))
    end
  end
end
