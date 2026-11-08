require 'rails_helper'

# #2695: a saved audience written from rows already resolved to contacts, the same one the spreadsheet flow leaves.
RSpec.describe CampaignJourney::AudienceWriter do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:mobile) { create(:contact, account: account, name: ' Mariana  Souza ', phone_number: '+5511987654321', email: 'Mari@Example.com') }
  let(:only_email) { create(:contact, account: account, name: 'Só e-mail', email: 'so@example.com') }

  def row(contact, **extra)
    described_class::Row.new(contact_id: contact.id, name: contact.name, phone: ConversationAudience::Reach.phone(contact),
                             email: ConversationAudience::Reach.email(contact), **extra)
  end

  def writer(**)
    described_class.new(account, user: user, source: 'teste', **)
  end

  it 'saves a completed audience of the audience flow with the source the caller gives' do
    audience = writer(options: { 'origem_id' => 7 }).perform('Leads', [row(mobile), row(only_email)])

    expect(audience).to be_audience
    expect(audience).to have_attributes(status: 'completed', name: 'Leads', campaign_name: 'Leads', user: user, total_rows: 2,
                                        valid_rows: 2, imported_contacts_count: 2, existing_contacts_count: 2)
    expect(audience.options).to eq('default_country' => 'BR', 'flow' => CampaignImport::AUDIENCE_FLOW, 'create_companies' => false,
                                   'source' => 'teste', 'origem_id' => 7)
  end

  it 'writes one imported row per person, in order, with the hashes the send checks again' do
    phone = ConversationAudience::Reach.phone(mobile)

    audience = writer.perform('Leads', [row(mobile, company_name: 'Acme'), row(only_email)])

    first, second = audience.campaign_import_rows.order(:row_number).to_a
    expect(first).to have_attributes(
      contact_id: mobile.id, row_number: 1, status: 'imported', was_existing_contact: true, raw_name: ' Mariana  Souza ',
      normalized_name: 'Mariana Souza', normalized_phone_hash: phone.hash, raw_phone_masked: phone.masked,
      normalized_email_hash: Digest::SHA256.hexdigest('mari@example.com'), company_name: 'Acme', extra_values: {}
    )
    expect(second).to have_attributes(contact_id: only_email.id, row_number: 2, normalized_phone_hash: nil, email_masked: be_present)
    expect(CampaignJourney::AudienceContacts.whatsapp_contact_ids(audience, account: account)).to eq([mobile.id])
  end

  it 'recounts the channels from the contacts' do
    audience = writer.perform('Leads', [row(mobile), row(only_email)])

    expect(audience.channels).to include('whatsapp' => { 'enabled' => true, 'count' => 1 },
                                         'email' => { 'enabled' => true, 'count' => 2 },
                                         'sms' => { 'enabled' => false, 'count' => 1 })
  end

  it 'keeps the extra columns and their types for the message' do
    audience = writer(columns: described_class::Columns.new(%w[Cidade Aniversário], { 'Aniversário' => 'data' }))
               .perform('Leads', [row(mobile, extra_values: { 'Cidade' => 'BH', 'Aniversário' => '1990-05-04' })])

    expect(audience.extra_columns).to eq(%w[Cidade Aniversário])
    expect(CampaignImports::ColumnTypes.stored(audience)).to eq('Aniversário' => 'data')
    expect(CampaignJourney::AudienceColumns.row_values(audience, mobile.id)).to eq('cidade' => 'BH', 'aniversario' => '1990-05-04')
  end

  it 'gives the same row attributes perform writes, for a person added to an audience later' do
    person = row(mobile, company_name: 'Acme', extra_values: { 'Cidade' => 'BH' })

    stored = writer.perform('Leads', [person]).campaign_import_rows.sole
    attributes = described_class.row_attributes(person)

    expect(stored.attributes.symbolize_keys.slice(*attributes.keys)).to eq(attributes)
  end

  it 'recounts the channels of an audience that already exists after its rows change' do
    audience = writer.perform('Leads', [row(mobile), row(only_email)])
    audience.campaign_import_rows.where(contact_id: mobile.id).delete_all

    expect(described_class.recount_channels(audience).reload.channels)
      .to include('whatsapp' => { 'enabled' => false, 'count' => 0 }, 'email' => { 'enabled' => true, 'count' => 1 })
  end

  it 'refuses an option the writer sets itself, naming it' do
    expect { writer(options: { 'source' => 'outra', 'flow' => 'x' }) }
      .to raise_error(ArgumentError, 'reserved option: source, flow')
  end

  it 'never saves an audience with nobody' do
    expect { writer.perform('Leads', []) }.to raise_error(described_class::Error, 'no_rows')
    expect(account.campaign_imports.count).to eq(0)
  end

  it 'leaves neither audience nor rows behind when the save fails half way' do
    allow(CampaignJourney::AudienceContacts).to receive(:recounted_channels).and_raise(ActiveRecord::RecordInvalid)

    expect { writer.perform('Leads', [row(mobile)]) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(account.campaign_imports.count).to eq(0)
    expect(CampaignImportRow.where(contact_id: mobile.id)).to be_empty
  end
end
