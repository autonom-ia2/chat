require 'rails_helper'

RSpec.describe Crm::Cards::ConversationLinker do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create_crm_inbox(account: account, members: [admin]) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:person) { account.contacts.create!(name: 'Mariana') }
  let(:other) { account.contacts.create!(name: 'Joao') }
  let(:conversation) { create_crm_conversation(account: account, inbox: inbox, contact: person) }
  let(:foreign_conversation) { create_crm_conversation(account: account, inbox: inbox, contact: other) }
  let(:card) do
    account.crm_cards.create!(pipeline: pipeline_and_stage.first, stage: pipeline_and_stage.last,
                              contact: person, owner: admin, title: 'Preserved negotiation', value_cents: 123_450)
  end

  it 'rejects the first conversation when it belongs to someone else without a partial write' do
    card
    foreign_conversation
    before = card.reload.attributes
    expect { described_class.new(card: card, conversation: foreign_conversation, actor: admin).link }
      .to raise_error(ActiveRecord::RecordInvalid)
    expect(card.reload.attributes).to eq(before)
    expect(card.card_conversations).to be_empty
    expect(card.activities).to be_empty
  end

  it 'rejects another person as a secondary conversation' do
    described_class.new(card: card, conversation: conversation, actor: admin).link
    before = card.reload.attributes
    expect { described_class.new(card: card, conversation: foreign_conversation, actor: admin).link }
      .to raise_error(ActiveRecord::RecordInvalid)
    expect(card.reload.attributes).to eq(before)
    expect(card.card_conversations.pluck(:conversation_id)).to eq([conversation.id])
  end

  it 'respects a legacy primary conversation when the explicit contact is absent' do
    card.update!(contact_id: nil, primary_conversation: conversation)
    expect { described_class.new(card: card, conversation: foreign_conversation, actor: admin, primary: true).link }
      .to raise_error(ActiveRecord::RecordInvalid)
    expect(card.reload.contact_id).to be_nil
    expect(card.conversation_id).to eq(conversation.id)
  end

  it 'respects secondary conversations when neither explicit contact nor primary is present' do
    card.update!(contact_id: nil)
    card.card_conversations.create!(account: account, conversation: conversation, linked_by: admin)
    expect { described_class.new(card: card, conversation: foreign_conversation, actor: admin).link }
      .to raise_error(ActiveRecord::RecordInvalid)
    expect(card.reload.contact_id).to be_nil
    expect(card.card_conversations.pluck(:conversation_id)).to eq([conversation.id])
  end

  it 'refreshes a stale card before allowing a conversation after a contact swap' do
    stale = Crm::Card.find(card.id)
    Crm::Cards::ContactLinker.new(card: card, contact: other, actor: admin).link
    expect { described_class.new(card: stale, conversation: conversation, actor: admin).link }
      .to raise_error(ActiveRecord::RecordInvalid)
    expect(card.reload.contact_id).to eq(other.id)
    expect(card.conversation_id).to be_nil
  end

  it 'keeps the current primary when a service was initialized before another link completed' do
    second = create_crm_conversation(account: account, inbox: inbox, contact: person)
    delayed = described_class.new(card: Crm::Card.find(card.id), conversation: second, actor: admin)
    described_class.new(card: card, conversation: conversation, actor: admin).link
    delayed.link
    expect(card.reload.conversation_id).to eq(conversation.id)
    expect(card.card_conversations.find_by!(conversation_id: second.id).is_primary).to be(false)
  end

  it 'preserves a newer primary when unlinking with a stale instance' do
    second = create_crm_conversation(account: account, inbox: inbox, contact: person)
    described_class.new(card: card, conversation: conversation, actor: admin).link
    delayed = described_class.new(card: Crm::Card.find(card.id), conversation: conversation, actor: admin)
    described_class.new(card: card, conversation: second, actor: admin, primary: true).link
    delayed.unlink
    expect(card.reload.conversation_id).to eq(second.id)
    expect(card.card_conversations.pluck(:conversation_id)).to eq([second.id])
  end

  it 'allows several conversations from the same person without changing business fields' do
    second = create_crm_conversation(account: account, inbox: inbox, contact: person)
    before = card.attributes.slice('title', 'value_cents', 'stage_id', 'pipeline_id', 'owner_id')
    described_class.new(card: card, conversation: conversation, actor: admin).link
    described_class.new(card: card, conversation: second, actor: admin).link
    expect(card.reload.contact_id).to eq(person.id)
    expect(card.linked_conversations.pluck(:id)).to contain_exactly(conversation.id, second.id)
    expect(card.attributes.slice(*before.keys)).to eq(before)
  end

  it 'rolls back both the card and link if its audit event fails' do
    card
    conversation
    before = card.reload.attributes
    logger = instance_double(Crm::ActivityLogger, perform: nil)
    allow(Crm::ActivityLogger).to receive(:new).and_return(logger)
    allow(logger).to receive(:perform).and_raise(StandardError, 'Audit unavailable')
    expect { described_class.new(card: card, conversation: conversation, actor: admin).link }
      .to raise_error(StandardError, 'Audit unavailable')
    expect(card.reload.attributes).to eq(before)
    expect(card.card_conversations).to be_empty
  end
end
