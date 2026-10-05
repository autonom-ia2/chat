require 'rails_helper'

# chat#1021: a WhatsApp API campaign fills the message with TemplateRenderer. The values it inserts
# (here the contact name) must reach the provider and the conversation literally, even when they
# look like Liquid; the variables the operator wrote in the message are still filled.
RSpec.describe WhatsappApiCampaigns::DeliveryEngine do
  include ActiveJob::TestHelper

  let(:provider_url) { 'https://waha.invalid/chatwoot' }
  let(:provider_bodies) { [] }

  before do
    allow(WhatsappApiCampaigns::Config).to receive(:enabled?).and_return(true)
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with('waha.invalid').and_return(['93.184.216.34'])
    stub_request(:post, provider_url).to_return do |request|
      provider_bodies << JSON.parse(request.body)
      { status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' } }
    end
  end

  def deliver_campaign(contact_name:, message_body:)
    account, user, inbox, label = create_account_user_inbox_and_label
    create_labelled_contact(account: account, label: label, name: contact_name, phone_number: '+5511987654321')
    campaign = create_whatsapp_api_campaign(account: account, user: user, inbox: inbox, label: label, message_body: message_body)
    WhatsappApiCampaigns::AudienceResolver.new(campaign).perform
    campaign.update!(status: :running)

    perform_enqueued_jobs(only: [EventDispatcherJob, WebhookJob]) { described_class.new(campaign).perform }

    campaign.whatsapp_api_campaign_recipients.first.reload.message
  end

  def provider_content
    created = provider_bodies.select { |body| body['event'] == 'message_created' }
    expect(created.size).to eq(1)
    created.first['content']
  end

  {
    '{{publico.plano}} Ana' => 'Olá {{publico.plano}} Ana!',
    '{% if true %}x{% endif %} Ana' => 'Olá {% if true %}x{% endif %} Ana!'
  }.each do |contact_name, expected|
    it "sends and records the contact name #{contact_name.inspect} literally" do
      message = deliver_campaign(contact_name: contact_name, message_body: 'Olá {{contact.name}}!')

      expect(message.content).to eq(expected)
      expect(provider_content).to eq(expected)
      expect(provider_content).to eq(message.content)
    end
  end

  it 'still fills the variables the operator wrote in the campaign message' do
    message = deliver_campaign(contact_name: 'Ana Maria', message_body: 'Olá {{ contact.first_name }}, tudo bem {{contact.name}}?')

    expect(message.content).to eq('Olá Ana, tudo bem Ana Maria?')
    expect(provider_content).to eq(message.content)
  end
end
