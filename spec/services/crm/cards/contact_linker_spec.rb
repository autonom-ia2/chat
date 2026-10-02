require 'rails_helper'

RSpec.describe Crm::Cards::ContactLinker do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:pipeline) { pipeline_and_stage.first }
  let(:stage) { pipeline_and_stage.last }
  let(:contact) { account.contacts.create!(name: 'Original', email: 'original@example.com') }
  let(:replacement) { account.contacts.create!(name: 'Replacement', email: 'replacement@example.com') }
  let(:inbox) { create_crm_inbox(account: account, members: [admin]) }
  let(:conversation) { create_crm_conversation(account: account, inbox: inbox, contact: contact) }
  let(:card) do
    account.crm_cards.create!(
      pipeline: pipeline, stage: stage, title: 'Commercial title', contact: contact,
      value_cents: 250_000, currency: 'BRL', owner: admin, score: 65,
      priority: :high, description: 'Keep the commercial context'
    )
  end
  let(:service) { described_class.new(card: card, contact: replacement, actor: admin) }

  it 'links an existing contact without changing the opportunity commercial data (M02)' do
    card.update!(contact_id: nil)
    service
    before = card.attributes.except('contact_id', 'last_activity_at', 'updated_at')

    expect { service.link }.not_to change(Contact, :count)

    expect(card.reload.contact_id).to eq(replacement.id)
    expect(card.attributes.except('contact_id', 'last_activity_at', 'updated_at')).to eq(before)
    expect(card.activities.last).to have_attributes(event_type: 'contact_linked', actor_id: admin.id)
    expect(card.activities.last.payload['contact_id']).to eq(replacement.id)
  end

  it 'records both contact IDs when replacing a link without deleting either contact (M02)' do
    original_id = contact.id
    replacement_id = replacement.id

    expect { service.link }.not_to change(Contact, :count)

    expect(card.activities.last.payload).to include('contact_id' => replacement_id, 'previous_contact_id' => original_id)
    expect(account.contacts.where(id: [original_id, replacement_id]).count).to eq(2)
  end

  it 'refuses a different contact when a legacy primary conversation exists without a join row (M02)' do
    card.update!(primary_conversation: conversation)
    before = card.attributes

    expect { service.link }.to raise_error(ActiveRecord::RecordInvalid) do |error|
      expect(error.record.errors.attribute_names).to include(:contact)
    end

    expect(card.reload.attributes).to eq(before)
    expect(conversation.reload.contact_id).to eq(contact.id)
    expect(card.activities).to be_empty
    expect(card.card_conversations).to be_empty
  end

  it 'refuses a different contact when only a secondary conversation exists (M02)' do
    card.card_conversations.create!(account: account, conversation: conversation, linked_by: admin)
    before = card.attributes

    expect { service.link }.to raise_error(ActiveRecord::RecordInvalid)

    expect(card.reload.attributes).to eq(before)
    expect(card.linked_conversations.pluck(:id)).to eq([conversation.id])
    expect(conversation.reload.contact_id).to eq(contact.id)
    expect(card.activities).to be_empty
  end

  it 'checks all linked conversations rather than just the primary one (M02)' do
    matching = create_crm_conversation(account: account, inbox: inbox, contact: replacement)
    card.update!(primary_conversation: matching)
    card.card_conversations.create!(account: account, conversation: matching, linked_by: admin, is_primary: true)
    card.card_conversations.create!(account: account, conversation: conversation, linked_by: admin)

    expect { service.link }.to raise_error(ActiveRecord::RecordInvalid)
    expect(card.reload.contact_id).to eq(contact.id)
    expect(card.linked_conversations.count).to eq(2)
  end

  it 'allows a contact that owns all primary and secondary conversations (M02)' do
    card.update!(contact_id: nil, primary_conversation: conversation)
    card.card_conversations.create!(account: account, conversation: conversation, linked_by: admin, is_primary: true)
    matching = described_class.new(card: card, contact: contact, actor: admin)

    expect { matching.link }.to change { card.reload.contact_id }.from(nil).to(contact.id)
    expect(card.reload.conversation_id).to eq(conversation.id)
    expect(conversation.reload.contact_id).to eq(contact.id)
  end

  it 'treats a repeated link to the same contact as a no-op (M02)' do
    service.link
    before = card.reload.attributes
    repeated = described_class.new(card: Crm::Card.find(card.id), contact: replacement, actor: admin)

    expect { repeated.link }.not_to change(Crm::Activity, :count)
    expect(card.reload.attributes).to eq(before)
  end

  it 'reads the current persisted contact before recording a swap from a stale card instance (M02)' do
    stale = Crm::Card.find(card.id)
    service.link

    described_class.new(card: stale, contact: contact, actor: admin).link

    expect(card.reload.contact_id).to eq(contact.id)
    expect(card.activities.order(:id).last.payload).to include(
      'contact_id' => contact.id, 'previous_contact_id' => replacement.id
    )
  end

  it 'checks a primary conversation added after the service card instance was loaded (M02)' do
    card
    card.primary_conversation
    Crm::Card.find(card.id).update!(primary_conversation: conversation)

    expect { service.link }.to raise_error(ActiveRecord::RecordInvalid)
    expect(card.reload.contact_id).to eq(contact.id)
    expect(card.conversation_id).to eq(conversation.id)
  end

  it 'rolls back the contact change when activity recording fails (M02)' do
    card
    replacement
    before = card.attributes
    logger = instance_double(Crm::ActivityLogger)
    allow(Crm::ActivityLogger).to receive(:new).and_return(logger)
    allow(logger).to receive(:perform).and_raise(StandardError, 'simulated activity failure')

    expect { service.link }.to raise_error(StandardError, 'simulated activity failure')
    expect(card.reload.attributes).to eq(before)
    expect(card.activities).to be_empty
  end

  it 'preserves the existing same-account validation (M02)' do
    foreign = create(:contact)
    original_id = card.contact_id

    expect do
      described_class.new(card: card, contact: foreign, actor: admin).link
    end.to raise_error(ActiveRecord::RecordInvalid)

    expect(card.reload.contact_id).to eq(original_id)
    expect(card.activities).to be_empty
  end

  it 'unlinks only the contact association without deleting the person or conversations (M02)' do
    card.update!(primary_conversation: conversation)
    card.card_conversations.create!(account: account, conversation: conversation, linked_by: admin)
    service
    before = card.attributes.except('contact_id', 'last_activity_at', 'updated_at')

    expect { service.unlink }.not_to change(Contact, :count)

    expect(card.reload.contact_id).to be_nil
    expect(card.attributes.except('contact_id', 'last_activity_at', 'updated_at')).to eq(before)
    expect(card.linked_conversations.pluck(:id)).to eq([conversation.id])
    expect(card.activities.last.payload['contact_id']).to eq(contact.id)
    expect(conversation.reload.contact_id).to eq(contact.id)
  end

  it 'treats a repeated unlink as a no-op (M02)' do
    service.unlink
    before = card.reload.attributes

    expect { service.unlink }.not_to change(Crm::Activity, :count)
    expect(card.reload.attributes).to eq(before)
  end

  it 'records the actual removed contact when unlinking through a stale instance (M02)' do
    stale = Crm::Card.find(card.id)
    service.link

    described_class.new(card: stale, contact: contact, actor: admin).unlink

    expect(card.reload.contact_id).to be_nil
    expect(card.activities.order(:id).last.payload['contact_id']).to eq(replacement.id)
  end
end
