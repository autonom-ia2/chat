require 'rails_helper'

# #2277: the people kept become a saved audience the send treats like a spreadsheet one.
RSpec.describe ConversationAudience::Save do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:search) do
    ConversationAudienceSearch.create!(account: account, user: user, request: 'quem cotou', period: '30d', status: 'done')
  end
  let(:mobile) { create(:contact, account: account, name: 'Mariana', phone_number: '+5511987654321', email: 'Mari@Example.com') }
  let(:landline) { create(:contact, account: account, name: 'Fixo', phone_number: '+551133334444') }
  let(:opted_out) { create(:contact, account: account, name: 'Não quer', phone_number: '+5511912345678', opted_out_at: 1.day.ago) }

  def found(contact, group = 'certeza')
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact)
    ConversationAudiencePerson.create!(search: search, contact: contact, conversation: conversation, group: group, reason: 'Cotou')
  end

  it 'creates a completed audience with the rows the send reads, and marks the search saved' do
    people = [found(mobile), found(landline), found(opted_out)]

    audience = described_class.new(search, user: user, name: ' Cotaram ', person_ids: people.map(&:id)).perform

    expect(audience).to have_attributes(status: 'completed', name: 'Cotaram', valid_rows: 1, imported_contacts_count: 1)
    expect(audience).to be_audience
    expect(audience.channels).to include('whatsapp' => include('enabled' => true, 'count' => 1),
                                         'email' => include('enabled' => true, 'count' => 1))
    expect(CampaignJourney::AudienceContacts.whatsapp_contact_ids(audience, account: account)).to eq([mobile.id])
    expect(audience.campaign_import_rows.first).to have_attributes(status: 'imported', contact_id: mobile.id, row_number: 1)
    expect(search.reload).to have_attributes(status: 'saved', campaign_import_id: audience.id)
  end

  it 'keeps someone with only an e-mail, so an account that sends by e-mail gets the whole audience' do
    only_email = create(:contact, account: account, name: 'Só e-mail', email: 'so@example.com')

    audience = described_class.new(search, user: user, name: 'E-mail', person_ids: [found(only_email).id]).perform

    expect(audience.valid_rows).to eq(1)
    expect(audience.channels).to include('email' => include('enabled' => true, 'count' => 1), 'whatsapp' => include('enabled' => false))
    expect(audience.campaign_import_rows.first).to have_attributes(contact_id: only_email.id, normalized_phone_hash: nil,
                                                                   email_masked: be_present)
  end

  it 'keeps the company, the city and the custom attributes as columns the message can use' do
    account.update!(locale: 'pt_BR')
    { 'time' => ['Time do coração', 'text'], 'aniversario' => %w[Aniversário date], 'vazio' => ['Ninguém tem', 'text'] }
      .each do |key, (name, type)|
        create(:custom_attribute_definition, account: account, attribute_model: 'contact_attribute', attribute_key: key,
                                             attribute_display_name: name, attribute_display_type: type)
      end
    mobile.update!(custom_attributes: { 'time' => 'Cruzeiro', 'aniversario' => '1990-05-04T00:00:00.000Z' },
                   additional_attributes: { 'city' => 'Belo Horizonte', 'company_name' => 'João X' })

    audience = described_class.new(search, user: user, name: 'Cruzeirenses', person_ids: [found(mobile).id]).perform

    expect(audience.extra_columns).to eq(['Cidade', 'Time do coração', 'Aniversário'])
    expect(CampaignImports::ColumnTypes.stored(audience)).to eq('Aniversário' => 'data')
    expect(audience.campaign_import_rows.first).to have_attributes(
      company_name: 'João X', extra_values: { 'Cidade' => 'Belo Horizonte', 'Time do coração' => 'Cruzeiro', 'Aniversário' => '1990-05-04' }
    )
    expect(CampaignJourney::AudienceColumns.row_values(audience, mobile.id)).to include('time_do_coracao' => 'Cruzeiro', 'cidade' => 'Belo Horizonte')
  end

  it 'never lets an attribute take a key the message fills by itself, like the company' do
    create(:custom_attribute_definition, account: account, attribute_model: 'contact_attribute', attribute_key: 'empresa_crm',
                                         attribute_display_name: 'Empresa', attribute_display_type: 'text')
    mobile.update!(custom_attributes: { 'empresa_crm' => 'Outra' }, additional_attributes: { 'company_name' => 'João X' })

    audience = described_class.new(search, user: user, name: 'Com empresa', person_ids: [found(mobile).id]).perform

    expect(audience.extra_columns).to eq(['Empresa (2)'])
    expect(CampaignJourney::AudienceColumns.row_values(audience, mobile.id)).to eq('empresa_2' => 'Outra')
    expect(audience.campaign_import_rows.first.company_name).to eq('João X')
  end

  it 'leaves the contact data out when the person saving does not read contacts' do
    agent = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: %w[campaign_manage conversation_view])
    agent.account_users.find_by(account: account).update!(custom_role: role)
    create(:inbox_member, user: agent, inbox: inbox)
    search.update!(user: agent)
    create(:custom_attribute_definition, account: account, attribute_model: 'contact_attribute', attribute_key: 'time',
                                         attribute_display_name: 'Time', attribute_display_type: 'text')
    mobile.update!(custom_attributes: { 'time' => 'Cruzeiro' }, additional_attributes: { 'city' => 'BH', 'company_name' => 'João X' })

    audience = described_class.new(search, user: agent, name: 'Sem dados', person_ids: [found(mobile).id]).perform

    expect(audience.extra_columns).to eq([])
    expect(audience.campaign_import_rows.first).to have_attributes(company_name: nil, extra_values: {}, contact_id: mobile.id)
  end

  it 'never makes two audiences from the same search' do
    person = found(mobile)
    described_class.new(search, user: user, name: 'Uma', person_ids: [person.id]).perform

    expect { described_class.new(search, user: user, name: 'Duas', person_ids: [person.id]).perform }
      .to raise_error(described_class::Error, 'already_saved')
    expect(account.campaign_imports.count).to eq(1)
  end

  it 'saves only people of this search' do
    other = ConversationAudienceSearch.create!(account: account, user: user, request: 'outra', period: '30d')
    stranger = ConversationAudiencePerson.create!(search: other, contact: mobile, group: 'certeza',
                                                  conversation: create(:conversation, account: account, inbox: inbox, contact: mobile))

    expect { described_class.new(search, user: user, name: 'X', person_ids: [stranger.id]).perform }
      .to raise_error(described_class::Error, 'no_people')
  end

  it 'asks for a name' do
    expect { described_class.new(search, user: user, name: ' ', person_ids: [found(mobile).id]).perform }
      .to raise_error(described_class::Error, 'name_required')
  end
end
