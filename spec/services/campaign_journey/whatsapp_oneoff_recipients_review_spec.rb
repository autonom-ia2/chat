require 'rails_helper'

# #1005 review fixes on the WhatsApp Oficial send to an audience (A1, M1, M3, B4, B6).
RSpec.describe CampaignJourney::WhatsappOneoffRecipients, :aggregate_failures do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  let(:channel) { journey_cloud_channel(account) }
  let(:mapping) { { 'name' => 0, 'phone' => 1, 'email' => 2 } }
  let(:content) do
    "Nome,Celular,Email,Vencimento\nAna Souza,11987654321,,10/2026\nBia Lima,,bia@beta.com.br,11/2026\nCaio Reis,31987654321,,12/2026\n"
  end
  let!(:audience) { saved_audience(account: account, user: user, content: content, mapping: mapping) }

  def journey_campaign(bindings: {}, defaults: {}, message: 'Olá {{1}}, sua apólice vence em {{2}}. {{3}}')
    campaign = create(:campaign, account: account, inbox: channel.inbox, audience: [], template_params: journey_template_params,
                                 message: message)
    CampaignAudienceLink.create!(account: account, campaign: campaign, campaign_import: audience,
                                 variable_bindings: bindings, variable_defaults: defaults)
    campaign
  end

  def contact_named(name)
    account.contacts.find_by!(name: name)
  end

  def recipient_of(campaign, name)
    CampaignRecipient.find_by(campaign: campaign, contact: contact_named(name))
  end

  def body_texts(message)
    message.dig('template', 'components').find { |component| component['type'] == 'body' }['parameters'].pluck('text')
  end

  describe 'A1: who may receive WhatsApp' do
    it 'never sends WhatsApp to a row that only had an email, even if the contact got a phone later' do
      sent = stub_graph_messages
      contact_named('Bia Lima').update!(phone_number: '+5521987654321')

      Whatsapp::OneoffCampaignService.new(campaign: journey_campaign).perform

      expect(sent.pluck('to')).to contain_exactly('+5511987654321', '+5531987654321')
      expect(recipient_of(Campaign.last, 'Bia Lima')).to be_nil
    end

    it 'does not send when the contact phone no longer matches the phone of the row' do
      sent = stub_graph_messages
      contact_named('Caio Reis').update!(phone_number: '+5541999990000')

      Whatsapp::OneoffCampaignService.new(campaign: journey_campaign).perform

      expect(sent.pluck('to')).to eq(['+5511987654321'])
    end

    it 'still sends to a contact stored without the 9th digit that the row matched' do
      legacy = account.contacts.create!(name: 'Dora Legada', phone_number: '+554588887777')
      sent = stub_graph_messages
      audience_with_legacy = saved_audience(account: account, user: user, content: "Nome,Celular\nDora,45988887777\n")
      campaign = create(:campaign, account: account, inbox: channel.inbox, audience: [], template_params: journey_template_params)
      CampaignAudienceLink.create!(account: account, campaign: campaign, campaign_import: audience_with_legacy)

      Whatsapp::OneoffCampaignService.new(campaign: campaign).perform

      expect(sent.pluck('to')).to eq(['+554588887777'])
      expect(CampaignRecipient.find_by!(campaign: campaign, contact: legacy)).to be_sent
    end

    it 'fails closed when the WhatsApp channel of the audience is off at send time' do
      sent = stub_graph_messages
      campaign = journey_campaign
      audience.update!(channels: audience.channels.merge('whatsapp' => audience.channels['whatsapp'].merge('enabled' => false)))

      Whatsapp::OneoffCampaignService.new(campaign: campaign).perform

      expect(sent).to be_empty
      expect(CampaignRecipient.where(campaign: campaign).pluck(:status, :error_message).uniq)
        .to eq([['skipped', CampaignJourney::AudienceContacts::CHANNEL_DISABLED_REASON]])
      expect(campaign.reload).to be_completed
    end

    it 'keeps the audience channel count equal to the contacts the send reaches' do
      contact_named('Caio Reis').update!(phone_number: '+5541999990000')

      count = CampaignJourney::AudienceContacts.whatsapp_contact_ids(audience, account: account).size

      expect(count).to eq(1)
    end
  end

  # M1: Meta refuses parameters with line breaks, tabs or long runs of spaces.
  it 'squishes line breaks, tabs and repeated spaces in every resolved value' do
    sent = stub_graph_messages
    audience.campaign_import_rows.find_by(row_number: 2).update!(extra_values: { 'Vencimento' => "10/\n2026\t  fim" })
    campaign = journey_campaign(bindings: { '2' => { 'source' => 'column', 'value' => 'Vencimento' },
                                            '3' => { 'source' => 'fixed', 'value' => "Equipe\n\nHub2You" } })

    Whatsapp::OneoffCampaignService.new(campaign: campaign).perform

    ana = sent.find { |message| message['to'] == '+5511987654321' }
    expect(body_texts(ana)).to include('10/ 2026 fim', 'Equipe Hub2You')
  end

  # B4: one pass, literal values: no chaining and no \0 / \& back-references.
  it 'inserts the values literally in the stored message, in a single pass' do
    stub_graph_messages
    audience.campaign_import_rows.find_by(row_number: 2).update!(extra_values: { 'Vencimento' => '{{3}} \0 \&' })
    campaign = journey_campaign(bindings: { '2' => { 'source' => 'column', 'value' => 'Vencimento' },
                                            '3' => { 'source' => 'fixed', 'value' => 'X' } })

    Whatsapp::OneoffCampaignService.new(campaign: campaign).perform

    expect(recipient_of(campaign, 'Ana Souza').message_content).to eq('Olá {{1}}, sua apólice vence em {{3}} \0 \&. X')
  end

  describe 'M3' do
    it 'keeps the upstream path for unlinked campaigns when CAMPAIGN_JOURNEY_ENABLED is off' do
      stub_graph_messages
      label = create(:label, account: account)
      account.contacts.create!(name: 'Rotulado', phone_number: '+5541987654321').update_labels([label.title])
      campaign = create(:campaign, account: account, inbox: channel.inbox, audience: [{ type: 'Label', id: label.id }],
                                   template_params: journey_template_params('1' => 'x', '2' => 'y', '3' => 'z'))
      allow(Liquid::CampaignTemplateService).to receive(:new).and_raise(ArgumentError, 'boom')

      with_modified_env(CAMPAIGN_JOURNEY_ENABLED: 'false') do
        expect { Whatsapp::OneoffCampaignService.new(campaign: campaign).perform }.to raise_error(ArgumentError)
      end
    end

    it 'never marks failed a message Meta accepted when saving sent fails' do
      sent = stub_graph_messages
      campaign = journey_campaign
      allow_any_instance_of(CampaignRecipient).to receive(:mark_sent!).and_raise(ActiveRecord::StatementInvalid, 'db') # rubocop:disable RSpec/AnyInstance
      allow(Rails.logger).to receive(:error)

      Whatsapp::OneoffCampaignService.new(campaign: campaign).perform

      expect(sent.size).to eq(2)
      expect(CampaignRecipient.where(campaign: campaign).pluck(:status).uniq).to eq(['sent'])
    end
  end

  # B6: recipients are walked in batches, never loaded all at once.
  it 'hands the recipients to the send loop lazily' do
    stub_graph_messages
    campaign = journey_campaign
    service = Whatsapp::OneoffCampaignService.new(campaign: campaign)
    received = nil
    allow(service).to receive(:process_recipients).and_wrap_original do |original, recipients|
      received = recipients
      original.call(recipients)
    end

    service.perform

    expect(received).not_to be_a(Array)
    expect(CampaignRecipient.where(campaign: campaign).sent.count).to eq(2)
  end
end
