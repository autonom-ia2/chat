require 'rails_helper'

RSpec.describe Enterprise::Whatsapp::OneoffCampaignService do
  let(:account) { create(:account) }
  let(:whatsapp_channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
  end
  let(:whatsapp_inbox) { whatsapp_channel.inbox }
  let(:label) { create(:label, account: account) }
  let(:template_params) do
    {
      'name' => 'ticket_status_updated',
      'namespace' => '23423423_2342423_324234234_2343224',
      'category' => 'UTILITY',
      'language' => 'en',
      'processed_params' => { 'body' => { 'name' => 'John', 'ticket_id' => '2332' } }
    }
  end
  let(:campaign) do
    create(
      :campaign,
      inbox: whatsapp_inbox,
      account: account,
      audience: [{ type: 'Label', id: label.id }],
      template_params: template_params
    )
  end

  before do
    account.enable_features!(:whatsapp_campaign)
    stub_meta_template_lookup # #1329: Meta unavailable, the dispatch check reads channel.message_templates
    allow_any_instance_of(Whatsapp::OneoffCampaignService).to receive(:channel).and_return(whatsapp_channel) # rubocop:disable RSpec/AnyInstance
  end

  it 'marks contacts without phone or BSUID as skipped' do
    contact = create(:contact, account: account, phone_number: nil)
    contact.update_labels([label.title])

    expect(whatsapp_channel).not_to receive(:send_template)

    Whatsapp::OneoffCampaignService.new(campaign: campaign).perform

    expect(CampaignRecipient.find_by!(campaign: campaign, contact: contact)).to be_skipped
  end

  it 'marks phone-less contacts with multiple WhatsApp identities as skipped' do
    contact = create(:contact, account: account, phone_number: nil)
    contact.update_labels([label.title])
    create(:contact_inbox, contact: contact, inbox: whatsapp_inbox, source_id: 'IN.2081978709342942')
    create(:contact_inbox, contact: contact, inbox: whatsapp_inbox, source_id: 'IN.2081978709342943')

    expect(whatsapp_channel).not_to receive(:send_template)

    Whatsapp::OneoffCampaignService.new(campaign: campaign).perform

    expect(CampaignRecipient.find_by!(campaign: campaign, contact: contact)).to be_skipped
  end

  it 'marks blocked BSUID-only authentication-template recipients as skipped' do
    contact = create(:contact, account: account, phone_number: nil)
    contact.update_labels([label.title])
    create(:contact_inbox, contact: contact, inbox: whatsapp_inbox, source_id: 'IN.2081978709342942')
    # #1329: approved, sendable and with the category the campaign recorded, so the dispatch check lets
    # the send reach Whatsapp::AuthenticationTemplateGuard, which skips the BSUID-only recipient.
    whatsapp_channel.update!(
      message_templates: [
        {
          'name' => 'ticket_status_updated',
          'language' => 'en',
          'status' => 'APPROVED',
          'category' => 'AUTHENTICATION',
          'components' => [{ 'type' => 'BODY', 'text' => 'Hello {{name}}, ticket {{ticket_id}}' }]
        }
      ]
    )
    campaign.update!(template_params: template_params.merge('category' => 'AUTHENTICATION'))

    expect(whatsapp_channel).not_to receive(:send_template)

    Whatsapp::OneoffCampaignService.new(campaign: campaign).perform

    expect(CampaignRecipient.find_by!(campaign: campaign, contact: contact)).to be_skipped
  end

  describe 'recusa de mensagens ativas (chat#737)' do
    it 'pula o contato que recusou, com motivo, e não envia' do
      contact = create(:contact, :with_phone_number, account: account)
      contact.update_labels([label.title])
      contact.opt_out!(source: 'manual')

      expect(whatsapp_channel).not_to receive(:send_template)

      Whatsapp::OneoffCampaignService.new(campaign: campaign).perform

      recipient = CampaignRecipient.find_by!(campaign: campaign, contact: contact)
      expect(recipient).to be_skipped
      expect(recipient.error_message).to eq('opted_out')
      expect(campaign.reload).to be_completed
    end

    it 'reconfere antes de cada mensagem: quem recusa durante o disparo não recebe' do
      first, second = create_list(:contact, 2, :with_phone_number, account: account)
      [first, second].each { |contact| contact.update_labels([label.title]) }
      sent_to = []
      allow(whatsapp_channel).to receive(:send_template) do |to, *_args|
        sent_to << to
        second.opt_out!(source: 'prospecting')
        'wamid.primeiro'
      end

      Whatsapp::OneoffCampaignService.new(campaign: campaign).perform

      expect(sent_to.size).to eq(1)
      expect(CampaignRecipient.find_by!(campaign: campaign, contact: first)).to be_sent
      recipient = CampaignRecipient.find_by!(campaign: campaign, contact: second)
      expect(recipient).to be_skipped
      expect(recipient.error_message).to eq('opted_out')
    end

    it 'envia normalmente a quem não recusou' do
      contact = create(:contact, :with_phone_number, account: account)
      contact.update_labels([label.title])

      expect(whatsapp_channel).to receive(:send_template).once.and_return('wamid.ok')

      Whatsapp::OneoffCampaignService.new(campaign: campaign).perform

      expect(CampaignRecipient.find_by!(campaign: campaign, contact: contact)).to be_sent
    end
  end

  # #2686: the "all contacts" audience of an automation campaign is the whole account. Recipients are created with one
  # insert per batch of contacts, not one find_or_create_by! per contact, and stay idempotent per campaign + contact.
  describe 'recipients in batches' do
    let(:service) { Whatsapp::OneoffCampaignService.new(campaign: campaign) }

    def insert_many_contacts(total)
      now = Time.current
      Contact.insert_all(Array.new(total) { |i| { account_id: account.id, name: "Contato #{i}", created_at: now, updated_at: now } }) # rubocop:disable Rails/SkipsModelValidations
    end

    def recipient_inserts(&)
      inserts = []
      callback = ->(*, payload) { inserts << payload[:sql] if payload[:sql].start_with?('INSERT INTO "campaign_recipients"') }
      ActiveSupport::Notifications.subscribed(callback, 'sql.active_record', &)
      inserts
    end

    before { campaign.update!(audience: Autonomia::Automacao::CampanhaSemEtiquetas.todos) }

    it 'creates 2,500 recipients with one insert per batch, not one per contact', :aggregate_failures do
      insert_many_contacts(2_500)

      inserts = recipient_inserts { service.send(:create_recipients, []).to_a }

      expect(inserts.size).to eq(3)
      expect(campaign.campaign_recipients.count).to eq(2_500)
      expect(campaign.campaign_recipients.queued.count).to eq(2_500)
    end

    it 'keeps the recipient a contact already has and never duplicates it', :aggregate_failures do
      first, second = create_list(:contact, 2, account: account)
      existing = CampaignRecipient.create!(account: account, campaign: campaign, contact: first, inbox: whatsapp_inbox, status: :sent)

      2.times { service.send(:create_recipients, []).to_a }

      expect(campaign.campaign_recipients.pluck(:contact_id)).to contain_exactly(first.id, second.id)
      expect(existing.reload).to be_sent
    end

    it 'returns the recipients of the audience only, with their contact' do
      contact = create(:contact, account: account)
      create(:contact)

      recipients = service.send(:create_recipients, []).to_a

      expect(recipients.map(&:contact)).to eq([contact])
    end
  end
end
