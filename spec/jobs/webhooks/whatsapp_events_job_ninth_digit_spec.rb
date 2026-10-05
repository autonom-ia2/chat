require 'rails_helper'

# #1005 D6: a reply from a number without the 9th digit lands in the imported contact's conversation
# (simulated WhatsApp Cloud webhook; the lookup comes from upstream fix 9550de83e4).
RSpec.describe Webhooks::WhatsappEventsJob, :aggregate_failures do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  let(:channel) { journey_cloud_channel(account) }
  let(:audience) { saved_audience(account: account, user: user, content: "Nome,Celular\nAna Souza,41988887777\n") }
  let(:imported_contact) { audience.campaign_import_rows.first.contact }

  def inbound_webhook(from:, wamid:)
    {
      object: 'whatsapp_business_account',
      entry: [{
        changes: [{
          field: 'messages',
          value: {
            metadata: { phone_number_id: channel.provider_config['phone_number_id'], display_phone_number: channel.phone_number.delete('+') },
            contacts: [{ profile: { name: 'Ana' }, wa_id: from }],
            messages: [{ from: from, id: wamid, timestamp: Time.current.to_i.to_s, text: { body: 'Quero renovar' }, type: 'text' }]
          }
        }]
      }]
    }.with_indifferent_access
  end

  after { Redis::Alfred.scan_each(match: 'MESSAGE_SOURCE_KEY::*') { |key| Redis::Alfred.delete(key) } }

  it 'reuses the imported contact (+55 41 98888-7777) for a reply from 554188887777' do
    stub_graph_messages
    campaign = create(:campaign, account: account, inbox: channel.inbox, audience: [], template_params: journey_template_params)
    CampaignAudienceLink.create!(account: account, campaign: campaign, campaign_import: audience)
    Whatsapp::OneoffCampaignService.new(campaign: campaign).perform
    expect(imported_contact.phone_number).to eq('+5541988887777')

    expect do
      described_class.perform_now(inbound_webhook(from: '554188887777', wamid: 'wamid.REPLY_1'))
    end.not_to change(Contact, :count)

    conversation = channel.inbox.conversations.last
    expect(conversation.contact).to eq(imported_contact)
    expect(conversation.messages.incoming.last.content).to eq('Quero renovar')
  end

  it 'appends the reply to the conversation the imported contact already has in the inbox' do
    contact_inbox = create(:contact_inbox, contact: imported_contact, inbox: channel.inbox, source_id: '5541988887777')
    conversation = create(:conversation, account: account, inbox: channel.inbox, contact: imported_contact, contact_inbox: contact_inbox)

    expect do
      described_class.perform_now(inbound_webhook(from: '554188887777', wamid: 'wamid.REPLY_2'))
    end.not_to change(Conversation, :count)

    expect(conversation.messages.incoming.last.content).to eq('Quero renovar')
  end
end
