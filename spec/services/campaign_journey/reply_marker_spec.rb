require 'rails_helper'

# #1002 — campaign mark in the CRM on reply (PRD D14, §6.7, §8.3; acceptance K1, K2, K5, K7).
RSpec.describe CampaignJourney::ReplyMarker do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, phone_number: '+5511987654321', email: 'Ana@Example.org') }

  around do |example|
    with_modified_env(CAMPAIGN_JOURNEY_ENABLED: 'true') { example.run }
  end

  def incoming_message(inbox, conversation: nil, created_at: Time.current)
    conversation ||= create(:conversation, account: account, inbox: inbox, contact: contact)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming,
                     content: 'Tenho interesse', created_at: created_at)
  end

  def campaign_touches(conversation)
    conversation.reload.additional_attributes['campaign_touches'] || []
  end

  describe 'WhatsApp Oficial (campaign_recipients)' do
    let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
    let(:inbox) { channel.inbox }
    let(:campaign) { create(:campaign, account: account, inbox: inbox, title: 'Renovação auto — outubro', campaign_type: :one_off) }

    def send_campaign(sent_at: 1.hour.ago, status: :sent, to: contact, on: campaign)
      CampaignRecipient.create!(account: account, campaign: on, contact: to, inbox: inbox, status: status, sent_at: sent_at)
    end

    # K1: the reply arrives through the WhatsApp Cloud webhook after a send.
    it 'marks the conversation when the recipient replies within 72h (webhook simulated)' do
      sender = '5511987654321'
      create(:contact_inbox, contact: contact, inbox: inbox, source_id: sender)
      send_campaign
      params = {
        phone_number: channel.phone_number, object: 'whatsapp_business_account',
        entry: [{ changes: [{ value: {
          contacts: [{ profile: { name: 'Ana' }, wa_id: sender }],
          messages: [{ from: sender, id: 'wamid.reply-1', text: { body: 'Quero saber mais' }, timestamp: Time.current.to_i.to_s, type: 'text' }]
        } }] }]
      }.with_indifferent_access

      perform_enqueued_jobs(only: [EventDispatcherJob, CampaignJourney::ReplyMarkJob]) do
        Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: inbox, params: params).perform
      end

      conversation = contact.conversations.find_by!(inbox: inbox)
      expect(conversation.additional_attributes['campaign']).to include(
        'source' => 'campaign_whatsapp', 'source_type' => 'campaign_whatsapp',
        'source_id' => "campaign:whatsapp:#{campaign.id}", 'headline' => 'Renovação auto — outubro'
      )
      expect(conversation.additional_attributes['campaign_source_ids']).to eq(["campaign:whatsapp:#{campaign.id}"])
    ensure
      Redis::Alfred.scan_each(match: 'MESSAGE_SOURCE_KEY::*') { |key| Redis::Alfred.delete(key) }
    end

    # K2: nothing is written at send time, and a contact who does not reply gets no mark.
    it 'writes no mark at send time nor for a recipient who does not reply' do
      silent = create(:contact, account: account, phone_number: '+5511911112222')
      silent_conversation = create(:conversation, account: account, inbox: inbox, contact: silent)
      send_campaign(to: silent)

      expect(silent_conversation.reload.additional_attributes).not_to have_key('campaign')
      expect(Conversation.where(account: account).where("additional_attributes ? 'campaign'")).to be_empty
    end

    it 'does not mark a reply after 72h, a recipient that failed, or a reply in another inbox' do
      send_campaign(sent_at: 73.hours.ago)
      late = incoming_message(inbox)
      expect(described_class.new(late).perform).to be(false)

      other_inbox = create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false).inbox
      expect(described_class.new(incoming_message(other_inbox)).perform).to be(false)

      CampaignRecipient.find_by!(campaign: campaign).update!(status: :failed, sent_at: 1.hour.ago)
      expect(described_class.new(incoming_message(inbox)).perform).to be(false)
      expect(Conversation.where(account: account).where("additional_attributes ? 'campaign'")).to be_empty
    end

    it 'marks once per conversation and campaign, and picks the most recent send' do
      older = create(:campaign, account: account, inbox: inbox, title: 'Setembro', campaign_type: :one_off)
      send_campaign(on: older, sent_at: 50.hours.ago)
      send_campaign(sent_at: 2.hours.ago)
      message = incoming_message(inbox)

      described_class.new(message).perform
      described_class.new(incoming_message(inbox, conversation: message.conversation)).perform

      expect(campaign_touches(message.conversation).pluck('source_id')).to eq(["campaign:whatsapp:#{campaign.id}"])
    end

    # K7: a conversation that came from a tracked link keeps the link as its origin.
    it 'keeps the first origin and adds the campaign as the next touch' do
      send_campaign
      conversation = create(:conversation, account: account, inbox: inbox, contact: contact)
      Ctwa::CampaignBuilder.attribute!(conversation, source_id: 'link:ABC234', source_type: 'tracked_link', headline: 'Feira 2026')

      described_class.new(incoming_message(inbox, conversation: conversation.reload)).perform

      attrs = conversation.reload.additional_attributes
      expect(attrs['campaign']).to include('source' => 'tracked_link', 'headline' => 'Feira 2026')
      expect(attrs['campaign_touches'].pluck('source')).to eq(%w[tracked_link campaign_whatsapp])
    end

    it 'does nothing with the journey off' do
      send_campaign
      message = incoming_message(inbox)

      with_modified_env(CAMPAIGN_JOURNEY_ENABLED: 'false') do
        perform_enqueued_jobs(only: [EventDispatcherJob, CampaignJourney::ReplyMarkJob]) do
          Rails.configuration.dispatcher.dispatch(Events::Types::MESSAGE_CREATED, Time.zone.now, message: message)
        end
      end

      expect(message.conversation.reload.additional_attributes).not_to have_key('campaign')
    end
  end

  describe 'WhatsApp API (whatsapp_api_campaign_recipients)' do
    it 'marks the conversation of a reply in the campaign inbox' do
      user = create(:user, account: account)
      inbox = create_whatsapp_api_inbox(account: account)
      label = account.labels.create!(title: 'clientes_wa')
      api_campaign = create_whatsapp_api_campaign(account: account, user: user, inbox: inbox, label: label)
      WhatsappApiCampaignRecipient.create!(whatsapp_api_campaign: api_campaign, account: account, inbox: inbox, contact: contact,
                                           status: :sent, sent_at: 3.hours.ago)
      message = incoming_message(inbox)

      described_class.new(message).perform

      expect(message.conversation.reload.additional_attributes['campaign']).to include(
        'source' => 'campaign_whatsapp', 'source_id' => "campaign:whatsapp_api:#{api_campaign.id}", 'headline' => 'Campanha WAHA'
      )
    end
  end

  # K5: the e-mail reply becomes a conversation in the replies inbox and gets the mark.
  describe 'E-mail (email_campaign_recipients)' do
    let(:email_inbox) { create(:inbox, account: account, channel: create(:channel_email, account: account)) }

    it 'marks the reply that arrives in the reply-to inbox of the verified domain' do
      identity = create(:email_sender_identity, account: account, reply_to_inbox_id: email_inbox.id)
      email_campaign = create(:email_campaign, account: account, sender_identity: identity, name: 'Novidades de outubro')
      create(:email_campaign_recipient, email_campaign: email_campaign, email: 'ana@example.org', status: :delivered, sent_at: 5.hours.ago)
      message = incoming_message(email_inbox)

      described_class.new(message).perform

      expect(message.conversation.reload.additional_attributes['campaign']).to include(
        'source' => 'campaign_email', 'source_id' => "campaign:email:#{email_campaign.id}", 'headline' => 'Novidades de outubro'
      )
    end

    it 'marks the reply that arrives in the mailbox a direct campaign was sent from' do
      email_campaign = create(:email_campaign, account: account, delivery_mode: :direct_inbox, sender_identity: nil,
                                               sender_inbox: email_inbox, name: 'Direto')
      create(:email_campaign_recipient, email_campaign: email_campaign, email: 'ana@example.org', status: :sent, sent_at: 1.hour.ago)
      message = incoming_message(email_inbox)

      described_class.new(message).perform

      expect(campaign_touches(message.conversation).pluck('source_id')).to eq(["campaign:email:#{email_campaign.id}"])
    end

    it 'ignores a campaign whose replies go to another inbox' do
      other_inbox = create(:inbox, account: account, channel: create(:channel_email, account: account))
      identity = create(:email_sender_identity, account: account, reply_to_inbox_id: other_inbox.id)
      email_campaign = create(:email_campaign, account: account, sender_identity: identity)
      create(:email_campaign_recipient, email_campaign: email_campaign, email: 'ana@example.org', status: :sent, sent_at: 1.hour.ago)

      expect(described_class.new(incoming_message(email_inbox)).perform).to be(false)
    end
  end
end
