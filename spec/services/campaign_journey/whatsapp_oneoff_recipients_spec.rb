require 'rails_helper'

# #1005: WhatsApp Oficial campaigns linked to an audience (N2, N3, D2, D4, D5, B1b).
RSpec.describe CampaignJourney::WhatsappOneoffRecipients, :aggregate_failures do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  let(:channel) { journey_cloud_channel(account) }
  let(:content) do
    "Nome,Celular,Vencimento\nAna Souza,11987654321,10/2026\nBia Lima,21987654321,\nCaio Reis,31987654321,12/2026\n"
  end
  let(:audience) { saved_audience(account: account, user: user, content: content) }

  def journey_campaign(bindings: {}, defaults: {}, template_params: journey_template_params, link_to: audience)
    campaign = create(:campaign, account: account, inbox: channel.inbox, audience: [], template_params: template_params,
                                 message: 'Olá {{1}}, sua apólice vence em {{2}}. {{3}}')
    CampaignAudienceLink.create!(account: account, campaign: campaign, campaign_import: link_to,
                                 variable_bindings: bindings, variable_defaults: defaults)
    campaign
  end

  def recipients(campaign)
    CampaignRecipient.where(campaign: campaign).includes(:contact).index_by { |recipient| recipient.contact.name }
  end

  def body_texts(message)
    message.dig('template', 'components').find { |component| component['type'] == 'body' }['parameters'].pluck('text')
  end

  # N2: exactly the audience's contacts, with no label involved.
  it 'sends to exactly the contacts of the audience and to no one else' do
    sent = stub_graph_messages
    outsider = account.contacts.create!(name: 'Fora', phone_number: '+5541987654321')
    campaign = journey_campaign

    Whatsapp::OneoffCampaignService.new(campaign: campaign).perform

    expect(sent.pluck('to')).to contain_exactly('+5511987654321', '+5521987654321', '+5531987654321')
    expect(CampaignRecipient.where(campaign: campaign).pluck(:contact_id)).not_to include(outsider.id)
    expect(recipients(campaign).values.map(&:status).uniq).to eq(['sent'])
    expect(campaign.reload).to be_completed
    expect(account.labels.count).to eq(0)
  end

  # N2 + B8: who refused messages before the send is not eligible (out of the total).
  it 'leaves contacts that refused messages out of the recipients' do
    stub_graph_messages
    audience.campaign_import_rows.order(:row_number).first.contact.opt_out!(source: 'manual')
    campaign = journey_campaign

    Whatsapp::OneoffCampaignService.new(campaign: campaign).perform

    expect(recipients(campaign).keys).to contain_exactly('Bia Lima', 'Caio Reis')
  end

  # D2: every eligible contact gets a queued recipient before the first message is sent.
  it 'registers every eligible contact as queued before sending' do
    statuses_at_first_send = nil
    campaign = journey_campaign
    stub_graph_messages(on_send: ->(_body) { statuses_at_first_send ||= CampaignRecipient.where(campaign: campaign).pluck(:status) })

    Whatsapp::OneoffCampaignService.new(campaign: campaign).perform

    expect(statuses_at_first_send).to eq(%w[queued queued queued])
    expect(CampaignRecipient.where(campaign: campaign).queued.count).to eq(0)
  end

  # D4: a provider error fails only that recipient, with Meta's readable reason; the others go on.
  it 'marks a provider error as failed with a readable reason and keeps sending to the others' do
    sent = stub_graph_messages(failing: ['+5521987654321'])
    campaign = journey_campaign

    Whatsapp::OneoffCampaignService.new(campaign: campaign).perform

    expect(sent.size).to eq(3)
    by_name = recipients(campaign)
    expect(by_name['Bia Lima']).to be_failed
    expect(by_name['Bia Lima'].error_message).to eq('Número sem WhatsApp')
    expect(by_name.values_at('Ana Souza', 'Caio Reis').map(&:status)).to eq(%w[sent sent])
  end

  # D2 + D4: an unexpected error on one recipient never leaves anyone without a final status.
  it 'fails a recipient on an unexpected error and leaves no recipient queued' do
    stub_graph_messages
    campaign = journey_campaign
    calls = 0
    allow(Whatsapp::TemplateProcessorService).to receive(:new).and_wrap_original do |original, **kwargs|
      calls += 1
      raise ArgumentError, 'boom' if calls == 2

      original.call(**kwargs)
    end
    allow(Rails.logger).to receive(:error)

    Whatsapp::OneoffCampaignService.new(campaign: campaign).perform

    statuses = CampaignRecipient.where(campaign: campaign).pluck(:status)
    expect(statuses.tally).to eq('sent' => 2, 'failed' => 1)
    expect(CampaignRecipient.where(campaign: campaign).failed.pick(:error_message)).to be_present
  end

  # D5 (#737): who refuses during the send is skipped before their message.
  it 'skips a contact that refuses messages while the campaign is sending' do
    campaign = journey_campaign
    caio = audience.campaign_import_rows.find_by(row_number: 4).contact
    sent = stub_graph_messages(on_send: ->(_body) { caio.opt_out!(source: 'manual') })

    Whatsapp::OneoffCampaignService.new(campaign: campaign).perform

    expect(sent.pluck('to')).not_to include('+5531987654321')
    expect(recipients(campaign)['Caio Reis']).to be_skipped
    expect(recipients(campaign)['Caio Reis'].error_message).to eq('opted_out')
  end

  # B1b: variables resolved per person from the contact, the audience column and a fixed text.
  it 'resolves contact, column and fixed variables per person and skips who misses one, with the reason' do
    sent = stub_graph_messages
    campaign = journey_campaign(bindings: {
                                  '1' => { 'source' => 'contact', 'value' => 'first_name' },
                                  '2' => { 'source' => 'column', 'value' => 'Vencimento' },
                                  '3' => { 'source' => 'fixed', 'value' => 'Equipe Hub2You' }
                                })

    Whatsapp::OneoffCampaignService.new(campaign: campaign).perform

    by_to = sent.index_by { |message| message['to'] }
    expect(body_texts(by_to.fetch('+5511987654321'))).to eq(['Ana', '10/2026', 'Equipe Hub2You'])
    expect(body_texts(by_to.fetch('+5531987654321'))).to eq(['Caio', '12/2026', 'Equipe Hub2You'])
    expect(by_to).not_to have_key('+5521987654321')
    bia = recipients(campaign)['Bia Lima']
    expect(bia).to be_skipped
    expect(bia.error_message).to eq('falta {{2}}')
    expect(recipients(campaign)['Ana Souza'].message_content).to eq('Olá Ana, sua apólice vence em 10/2026. Equipe Hub2You')
  end

  it 'uses the default text when the person has no value for a variable' do
    sent = stub_graph_messages
    campaign = journey_campaign(bindings: { '2' => { 'source' => 'column', 'value' => 'Vencimento' } }, defaults: { '2' => 'em breve' })

    Whatsapp::OneoffCampaignService.new(campaign: campaign).perform

    expect(sent.size).to eq(3)
    bia_message = sent.find { |message| message['to'] == '+5521987654321' }
    expect(body_texts(bia_message)).to include('em breve')
    expect(recipients(campaign)['Bia Lima']).to be_sent
  end

  it 'does not send twice when the same campaign is processed again' do
    sent = stub_graph_messages
    campaign = journey_campaign
    Whatsapp::OneoffCampaignService.new(campaign: campaign).perform
    campaign.update_columns(campaign_status: Campaign.campaign_statuses[:active]) # rubocop:disable Rails/SkipsModelValidations

    Whatsapp::OneoffCampaignService.new(campaign: campaign).perform

    expect(sent.size).to eq(3)
    expect(CampaignRecipient.where(campaign: campaign).count).to eq(3)
  end

  it 'sends to no one when the audience was deleted before the send' do
    sent = stub_graph_messages
    campaign = journey_campaign(link_to: nil)

    Whatsapp::OneoffCampaignService.new(campaign: campaign).perform

    expect(sent).to be_empty
    expect(campaign.reload).to be_completed
  end

  # N3: a campaign without a link keeps sending to its labels.
  it 'keeps the label audience for campaigns without an audience link' do
    sent = stub_graph_messages
    label = create(:label, account: account)
    labeled = account.contacts.create!(name: 'Rotulado', phone_number: '+5541987654321')
    labeled.update_labels([label.title])
    audience # contacts of an audience that this campaign does not use
    campaign = create(:campaign, account: account, inbox: channel.inbox, audience: [{ type: 'Label', id: label.id }],
                                 template_params: journey_template_params('1' => 'x', '2' => 'y', '3' => 'z'))

    Whatsapp::OneoffCampaignService.new(campaign: campaign).perform

    expect(sent.pluck('to')).to eq(['+5541987654321'])
    expect(CampaignRecipient.where(campaign: campaign).pluck(:contact_id, :status)).to eq([[labeled.id, 'sent']])
  end
end
