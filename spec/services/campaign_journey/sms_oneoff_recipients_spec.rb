require 'rails_helper'

# #1004: SMS campaigns linked to an audience (M3, D2, D4, D5, B1b, consent rule). Twilio and
# Bandwidth APIs are stubbed with WebMock; no real SMS is sent.
RSpec.describe CampaignJourney::SmsOneoffRecipients, :aggregate_failures do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  # Created before the audience: the sms badge is born on only with an SMS inbox connected.
  let!(:inbox) { journey_twilio_sms_inbox(account) }
  let(:mapping) { { 'name' => 0, 'phone' => 1, 'email' => 2 } }
  let(:content) do
    "Nome,Celular,Email,Vencimento\nAna Souza,11987654321,,10/2026\nBia Lima,,bia@beta.com.br,11/2026\n" \
      "Caio Reis,31987654321,,\n"
  end
  let!(:audience) { saved_audience(account: account, user: user, content: content, mapping: mapping) }
  let(:message) { 'Oi {{contact.first_name}}, vence {{publico.vencimento}}.' }

  def sms_campaign(text: message, defaults: {}, on: inbox, link: audience)
    campaign = create(:campaign, account: account, inbox: on, audience: [], title: 'Parcela outubro', message: text)
    CampaignAudienceLink.create!(account: account, campaign: campaign, campaign_import: link, variable_defaults: defaults) if link
    campaign
  end

  def send_sms(campaign)
    service = campaign.inbox.inbox_type == 'Sms' ? Sms::OneoffSmsCampaignService : Twilio::OneoffSmsCampaignService
    service.new(campaign: campaign).perform
  end

  def recipients(campaign)
    CampaignRecipient.where(campaign: campaign).includes(:contact).index_by { |recipient| recipient.contact.name }
  end

  def contact_named(name)
    account.contacts.find_by!(name: name)
  end

  # Consent: SMS uses the phone the row brought (the WhatsApp rule); the e-mail-only row never gets SMS.
  it 'sends one SMS to each audience phone, never to an e-mail-only row, and registers the provider id' do
    sent = stub_twilio_sms
    contact_named('Bia Lima').update!(phone_number: '+5521987654321')
    campaign = sms_campaign(defaults: { 'publico.vencimento' => 'em breve' })

    send_sms(campaign)

    expect(sent.pluck('To')).to contain_exactly('+5511987654321', '+5531987654321')
    expect(sent.pluck('Body')).to contain_exactly('Oi Ana, vence 10/2026.', 'Oi Caio, vence em breve.')
    by_name = recipients(campaign)
    expect(by_name.keys).to contain_exactly('Ana Souza', 'Caio Reis')
    expect(by_name.values.map(&:status).uniq).to eq(['sent'])
    expect(by_name.values.map(&:source_id)).to all(start_with('SM'))
    expect(by_name['Ana Souza'].message_content).to eq('Oi Ana, vence 10/2026.')
    expect(campaign.reload).to be_completed
    expect(WebMock).to have_requested(:post, CampaignJourneySmsHelpers::TWILIO_MESSAGES).times(2)
  end

  # D2: every eligible contact is queued before the first SMS; none is left without a status.
  it 'registers every eligible contact as queued before the first SMS' do
    campaign = sms_campaign(defaults: { 'publico.vencimento' => 'em breve' })
    statuses_at_first_send = nil
    stub_twilio_sms(on_send: ->(_body) { statuses_at_first_send ||= CampaignRecipient.where(campaign: campaign).pluck(:status) })

    send_sms(campaign)

    expect(statuses_at_first_send).to eq(%w[queued queued])
    expect(CampaignRecipient.where(campaign: campaign).queued.count).to eq(0)
  end

  # D4: the provider's refusal fails only that person, with Twilio's code and message.
  it 'marks a Twilio refusal as failed with the reason and keeps sending to the others' do
    sent = stub_twilio_sms(failing: { '+5511987654321' => [21_211, "The 'To' number is not a valid phone number."] })
    campaign = sms_campaign(defaults: { 'publico.vencimento' => 'em breve' })

    send_sms(campaign)

    expect(sent.size).to eq(2)
    ana = recipients(campaign)['Ana Souza']
    expect(ana).to be_failed
    expect([ana.error_code, ana.error_message]).to eq(['21211', "The 'To' number is not a valid phone number."])
    expect(recipients(campaign)['Caio Reis']).to be_sent
  end

  it 'marks an unexpected error before the provider accepted as failed and goes on' do
    stub_twilio_sms
    campaign = sms_campaign(defaults: { 'publico.vencimento' => 'em breve' })
    allow_any_instance_of(CampaignJourney::SmsMessage).to receive(:render_for).and_wrap_original do |render, contact| # rubocop:disable RSpec/AnyInstance
      raise ArgumentError, 'boom' if contact.name == 'Ana Souza'

      render.call(contact)
    end

    send_sms(campaign)

    expect(recipients(campaign)['Ana Souza'].error_message).to eq('Unexpected error while sending (ArgumentError)')
    expect(recipients(campaign)['Caio Reis']).to be_sent
  end

  # D5: who refuses during the send is skipped, read again before each SMS.
  it 'skips a contact that refused messages in the middle of the send' do
    caio = contact_named('Caio Reis')
    sent = stub_twilio_sms(on_send: ->(_body) { caio.opt_out!(source: 'manual') unless caio.reload.opted_out? })
    campaign = sms_campaign(defaults: { 'publico.vencimento' => 'em breve' })

    send_sms(campaign)

    expect(sent.size).to eq(1)
    expect(recipients(campaign)['Caio Reis'].status).to eq('skipped')
    expect(recipients(campaign)['Caio Reis'].error_message).to eq('opted_out')
  end

  it 'leaves contacts that refused before the send out of the recipients' do
    stub_twilio_sms
    contact_named('Ana Souza').opt_out!(source: 'manual')

    send_sms(campaign = sms_campaign(defaults: { 'publico.vencimento' => 'em breve' }))

    expect(recipients(campaign).keys).to eq(['Caio Reis'])
  end

  # B1b: no value and no default → skipped with "falta <coluna>" / "falta empresa".
  it 'skips a person without a token value and without a default' do
    sent = stub_twilio_sms

    send_sms(campaign = sms_campaign(text: '{{contact.company}}: vence {{publico.vencimento}}'))

    expect(sent).to be_empty
    expect(recipients(campaign).transform_values { |recipient| [recipient.status, recipient.error_message] })
      .to eq('Ana Souza' => ['skipped', 'falta empresa'], 'Caio Reis' => ['skipped', 'falta empresa, vencimento'])
  end

  it 'records everyone as skipped when the audience SMS badge is off at send time' do
    sent = stub_twilio_sms
    campaign = sms_campaign
    audience.update!(channels: audience.channels.merge('sms' => audience.channels['sms'].merge('enabled' => false)))

    send_sms(campaign)

    expect(sent).to be_empty
    expect(recipients(campaign).values.map { |recipient| [recipient.status, recipient.error_message] }.uniq)
      .to eq([['skipped', described_class::CHANNEL_DISABLED_REASON]])
    expect(campaign.reload).to be_completed
  end

  # The SMS badge is its own: WhatsApp off does not stop SMS.
  it 'sends SMS with the WhatsApp badge of the audience off' do
    sent = stub_twilio_sms
    audience.update!(channels: audience.channels.merge('whatsapp' => audience.channels['whatsapp'].merge('enabled' => false)))

    send_sms(sms_campaign(defaults: { 'publico.vencimento' => 'em breve' }))

    expect(sent.size).to eq(2)
  end

  describe 'Bandwidth' do
    let(:inbox) { journey_bandwidth_inbox(account) }

    # Bandwidth's own reason, with the phone masked (SafeLogMessage).
    it 'sends through Bandwidth with the message id as source id, and a refusal fails with the masked reason' do
      sent = stub_bandwidth_sms(failing: ['+5531987654321'])
      campaign = sms_campaign(defaults: { 'publico.vencimento' => 'em breve' })

      send_sms(campaign)

      expect(sent.pluck('to')).to contain_exactly('+5511987654321', '+5531987654321')
      by_name = recipients(campaign)
      expect([by_name['Ana Souza'].status, by_name['Ana Souza'].source_id]).to eq(%w[sent bw-5511987654321])
      expect([by_name['Caio Reis'].status, by_name['Caio Reis'].error_message]).to eq(['failed', "'to' +<DIGITS> is not a mobile number"])
    end
  end

  # Label (unlinked) campaigns keep Chatwoot's code, with the journey flag on.
  it 'leaves an old label SMS campaign to Chatwoot, without recipients' do
    sent = stub_twilio_sms
    label = account.labels.create!(title: 'clientes_sms')
    contact_named('Ana Souza').add_labels([label.title])
    campaign = create(:campaign, account: account, inbox: inbox, audience: [{ 'type' => 'Label', 'id' => label.id }], message: 'Oi')

    with_modified_env(CAMPAIGN_JOURNEY_ENABLED: 'true') { send_sms(campaign) }

    expect(sent.pluck('To')).to eq(['+5511987654321'])
    expect(CampaignRecipient.where(campaign: campaign)).to be_empty
    expect(campaign.reload).to be_completed
  end
end
