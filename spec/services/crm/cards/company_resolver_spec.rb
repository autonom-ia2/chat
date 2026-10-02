require 'rails_helper'

RSpec.describe Crm::Cards::CompanyResolver do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: create(:user, account: account)) }
  let(:pipeline) { pipeline_and_stage.first }
  let(:stage) { pipeline_and_stage.last }
  let(:contact_company) { create(:company, account: account, name: 'Empresa do contato') }
  let(:prospecting_company) { create(:company, account: account, name: 'Empresa da prospecção') }

  def create_card(metadata: {}, contact: nil)
    account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Oportunidade', contact: contact, metadata: metadata)
  end

  it 'prefers the current prospecting company over the contact company' do
    contact = account.contacts.create!(name: 'Pessoa', phone_number: '+5511987654321', company: contact_company)
    card = create_card(
      contact: contact,
      metadata: { 'autonomia_prospecting' => { 'company' => { 'id' => prospecting_company.id } } }
    )

    expect(described_class.for_card(card)).to eq(prospecting_company)
  end

  it 'falls back to the contact company for a regular card' do
    contact = account.contacts.create!(name: 'Pessoa', phone_number: '+5511987654321', company: contact_company)

    expect(described_class.for_card(create_card(contact: contact))).to eq(contact_company)
  end

  it 'ignores a prospecting company from another account' do
    foreign_company = create(:company, account: other_account, name: 'Empresa de outra conta')
    contact = account.contacts.create!(name: 'Pessoa', company: contact_company)
    card = create_card(
      contact: contact,
      metadata: { 'autonomia_prospecting' => { 'company' => { 'id' => foreign_company.id } } }
    )

    expect(described_class.for_card(card)).to be_nil
  end

  it 'does not fall back to the contact when the prospecting company id is stale' do
    contact = account.contacts.create!(name: 'Pessoa', company: contact_company)
    card = create_card(
      contact: contact,
      metadata: { 'autonomia_prospecting' => { 'company' => { 'id' => 999_999_999 } } }
    )

    expect(described_class.for_card(card)).to be_nil
  end

  it 'does not expose a contact company that belongs to another account' do
    foreign_company = create(:company, account: other_account)
    contact = account.contacts.create!(name: 'Pessoa', company: foreign_company)

    expect(described_class.for_card(create_card(contact: contact))).to be_nil
  end

  it 'resolves a collection without a company query for each card' do
    contact = account.contacts.create!(name: 'Pessoa', company: contact_company)
    first = create_card(contact: contact)
    cards = Array.new(8) do
      create_card(metadata: { 'autonomia_prospecting' => { 'company' => { 'id' => prospecting_company.id } } })
    end
    records = account.crm_cards.where(id: [first.id, *cards.map(&:id)]).to_a
    company_queries = []
    subscriber = lambda do |_name, _start, _finish, _id, payload|
      company_queries << payload[:sql] if payload[:sql].include?('FROM "companies"')
    end
    resolved = nil
    ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') do
      resolved = described_class.for_cards(records)
    end

    expect(company_queries.size).to be <= 2
    expect(resolved).to include(first.id => contact_company, cards.last.id => prospecting_company)
    expect(described_class.payload(resolved[cards.first.id])).to eq(id: prospecting_company.id, name: prospecting_company.name)
  end
end
