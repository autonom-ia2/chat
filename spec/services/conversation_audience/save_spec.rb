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
