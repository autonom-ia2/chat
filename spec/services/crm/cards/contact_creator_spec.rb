require 'rails_helper'

RSpec.describe Crm::Cards::ContactCreator do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:card) { account.crm_cards.create!(pipeline: pipeline_and_stage.first, stage: pipeline_and_stage.last, title: 'Existing') }
  let(:attributes) { { name: 'Registered lead', email: 'registered-part2@example.com' } }
  let(:service) { described_class.new(card: card, actor: admin, attributes: attributes) }

  it 'creates a lead in the card account without another opportunity' do
    card
    count = Crm::Card.count
    result = service.perform
    expect(result.id).to eq(card.id)
    expect(card.reload.contact).to have_attributes(account_id: account.id, contact_type: 'lead')
    expect(Crm::Card.count).to eq(count)
  end

  it 'uses the current persisted link when a second request already attached a contact' do
    card
    existing = account.contacts.create!(name: 'Another request', email: 'another-part2@example.com')
    Crm::Card.find(card.id).update!(contact: existing)
    expect { service.perform }.to raise_error(ActiveRecord::RecordInvalid)
    expect(account.contacts.count).to eq(1)
    expect(card.reload.contact_id).to eq(existing.id)
  end

  it 'allows the same phone in different accounts without linking the foreign contact' do
    foreign = create(:contact, phone_number: '+14155552671')
    described_class.new(card: card, actor: admin, attributes: { name: 'Local lead', phone_number: foreign.phone_number }).perform
    expect(card.reload.contact).to have_attributes(account_id: account.id, phone_number: foreign.phone_number)
    expect(card.contact_id).not_to eq(foreign.id)
  end

  it 'rolls back the person and card when audit recording fails' do
    card
    previous = card.attributes
    allow(Crm::ActivityLogger).to receive(:new).and_raise(StandardError, 'controlled audit failure')
    expect { service.perform }.to raise_error(StandardError, 'controlled audit failure')
    expect(account.contacts.count).to eq(0)
    expect(card.reload.attributes).to eq(previous)
  end

  it 'does not dispatch contact events for a rolled back registration' do
    card
    allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original
    allow(Crm::ActivityLogger).to receive(:new).and_raise(StandardError, 'controlled audit failure')
    expect { service.perform }.to raise_error(StandardError, 'controlled audit failure')
    expect(Rails.configuration.dispatcher).not_to have_received(:dispatch).with(Events::Types::CONTACT_CREATED, anything, anything)
  end

  it 'honors the caller transaction if a later step fails' do
    card
    expect do
      ActiveRecord::Base.transaction do
        service.perform
        raise 'controlled enclosing failure'
      end
    end.to raise_error(RuntimeError, 'controlled enclosing failure')
    expect(card.reload.contact_id).to be_nil
    expect(account.contacts).to be_empty
    expect(card.activities).to be_empty
  end

  it 'keeps an old name-only contact when its opportunity is archived' do
    described_class.new(card: card, actor: admin, attributes: { name: 'Name only' }).perform
    person = card.reload.contact
    person.update!(created_at: 40.days.ago)
    card.update!(status: :archived)
    expect { Internal::RemoveStaleContactsService.new(account: account).perform }.not_to change(Contact, :count)
    expect(Contact.exists?(person.id)).to be(true)
  end

  it 'does not delete a legacy visitor attached to an existing opportunity' do
    person = account.contacts.create!(name: 'Legacy CRM person', created_at: 40.days.ago)
    expect(person.contact_type).to eq('visitor')
    card.update!(contact: person)
    expect { Internal::RemoveStaleContactsService.new(account: account).perform }.not_to change(Contact, :count)
    expect(Crm::Card.exists?(card.id)).to be(true)
  end

  it 'does not delete a customer merely because identifying fields are empty' do
    person = account.contacts.create!(name: 'Known customer', contact_type: :customer, created_at: 40.days.ago)
    expect { Internal::RemoveStaleContactsService.new(account: account).perform }.not_to change(Contact, :count)
    expect(Contact.exists?(person.id)).to be(true)
  end

  it 'keeps identified contacts in a different account outside its resolved scope' do
    service.perform
    other_account = create(:account)
    foreign = other_account.contacts.create!(name: 'Foreign lead', contact_type: :lead)
    expect(account.contacts.resolved_contacts(use_crm_v2: false)).to include(card.contact)
    expect(account.contacts.resolved_contacts(use_crm_v2: false)).not_to include(foreign)
  end
end
