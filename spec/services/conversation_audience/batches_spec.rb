require 'rails_helper'

# #2277: the period's conversations split in reader batches of up to 20 conversations or 60 thousand characters.
RSpec.describe ConversationAudience::Batches do
  describe '.split' do
    it 'closes a batch at 20 conversations' do
      sizes = (1..45).index_with(100)

      expect(described_class.split(sizes).map { |ids, _chars| ids.size }).to eq([20, 20, 5])
    end

    it 'closes a batch before it passes the character limit, and a big conversation goes alone' do
      sizes = { 1 => 30_000, 2 => 25_000, 3 => 10_000, 4 => 60_000, 5 => 10 }

      expect(described_class.split(sizes)).to eq([[[1, 2], 55_000], [[3], 10_000], [[4], 60_000], [[5], 10]])
    end
  end

  describe '.build!' do
    let(:account) { create(:account) }
    let(:inbox) { create(:inbox, account: account) }
    let(:admin) { create(:user, account: account, role: :administrator) }
    let(:search) { ConversationAudienceSearch.create!(account: account, user: admin, request: 'quem cotou', period: '30d') }

    it 'writes the batches of the conversations active in the period, and rebuilds them from scratch' do
      recent = create(:conversation, account: account, inbox: inbox, last_activity_at: 2.days.ago)
      create(:message, account: account, inbox: inbox, conversation: recent, content: 'oi')
      old = create(:conversation, account: account, inbox: inbox)
      create(:message, account: account, inbox: inbox, conversation: old, content: 'antigo')
      old.update!(last_activity_at: 2.months.ago)

      described_class.build!(search)
      totals = described_class.build!(search)

      expect(totals).to include(conversations: 1, batches: 1)
      expect(search.batches.pluck(:number, :conversation_ids, :status)).to eq([[1, [recent.id], 'pending']])
    end
  end
end
