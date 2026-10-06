require 'rails_helper'

# #999: WhatsApp API inside the campaign journey (contract in docs/campaigns/publicos/api-999.md).
# The campaign goes to the audience contacts (N2) through the engine of today, and the
# {{contact.company}} token becomes the contact's company; without one the person is skipped
# with "falta empresa" unless the campaign has a default text (D7). Sending only records the
# outgoing message in the API inbox (no provider is called).
RSpec.describe 'Campaign journey WhatsApp API campaigns (#999)', :aggregate_failures, type: :request do
  around do |example|
    with_modified_env(CAMPAIGN_JOURNEY_ENABLED: 'true', WHATSAPP_API_CAMPAIGNS_ENABLED: 'true') { example.run }
  end

  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  let(:inbox) { create_whatsapp_api_inbox(account: account) }
  let(:audience) do
    saved_audience(account: account, user: user, content: "Nome,Celular\nAna Souza,11987654321\nBia Lima,21987654321\n")
  end

  before do
    allow(WhatsappApiCampaigns::Config).to receive(:enabled?).and_return(true)
    allow(WhatsappApiCampaigns::DeliveryJob).to receive(:perform_later)
    allow(WhatsappApiCampaigns::DeliveryJob).to receive(:set).and_return(WhatsappApiCampaigns::DeliveryJob)
    allow(WhatsappApiCampaigns::ScheduleDueCampaignsJob).to receive(:perform_later)
  end

  def create_campaign(audience_id: audience.id, **campaign)
    body = { campaign_import_id: audience_id, channel: 'whatsapp_api',
             campaign: { title: 'Renovação API', inbox_id: inbox.id, scheduled_at: nil,
                         message_body: 'Olá {{contact.first_name}}, da {{contact.company}}' }.merge(campaign) }
    post "/api/v1/accounts/#{account.id}/campaign_journey/campaigns", params: body, headers: { 'api_access_token' => user.access_token.token },
                                                                      as: :json
  end

  def give_company(name, company_name)
    audience
    company = Company.create!(account: account, name: company_name)
    account.contacts.find_by(name: name).update!(company: company)
  end

  def run_campaign(campaign)
    WhatsappApiCampaigns::Scheduler.new.perform
    3.times { WhatsappApiCampaigns::DeliveryEngine.new(campaign).perform }
    campaign.reload
  end

  def outcome(campaign)
    campaign.whatsapp_api_campaign_recipients.joins(:contact).order('contacts.name')
            .pluck('contacts.name', :status, :last_error_message)
  end

  it 'sends to the audience contacts and skips who has no company with "falta empresa" (D7, N2, E1)' do
    give_company('Ana Souza', 'Alfa Corretora')

    create_campaign

    expect(response).to have_http_status(:ok)
    payload = response.parsed_body
    expect(payload).to include('channel' => 'whatsapp_api', 'title' => 'Renovação API', 'inbox_id' => inbox.id, 'recipients_count' => 2)
    campaign = WhatsappApiCampaign.find(payload['id'])
    expect(campaign.audience).to eq([{ 'type' => 'CampaignAudience', 'id' => audience.id }])
    expect(CampaignAudienceLink.for_campaign(campaign).campaign_import).to eq(audience)
    expect(campaign.scheduled_at).to be <= Time.current

    run_campaign(campaign)

    expect(outcome(campaign)).to eq([['Ana Souza', 'sent', nil], ['Bia Lima', 'cancelled', 'falta empresa']])
    expect(Message.where(inbox: inbox).outgoing.pluck(:content)).to eq(['Olá Ana, da Alfa Corretora'])
    # E1 (WhatsApp): sent + failed + skipped = eligible audience.
    expect(campaign.sent_count + campaign.failed_count + campaign.cancelled_count).to eq(payload['recipients_count'])
    expect(campaign).to be_completed
  end

  it 'uses the default company text instead of skipping' do
    create_campaign(company_default: 'sua empresa')

    campaign = WhatsappApiCampaign.find(response.parsed_body['id'])
    expect(CampaignAudienceLink.for_campaign(campaign).variable_defaults).to eq('contact.company' => 'sua empresa')
    run_campaign(campaign)

    expect(outcome(campaign).map(&:second)).to eq(%w[sent sent])
    expect(Message.where(inbox: inbox).outgoing.pluck(:content)).to contain_exactly('Olá Ana, da sua empresa', 'Olá Bia, da sua empresa')
  end

  it 'keeps a message without the company token untouched and leaves contacts outside the audience out' do
    account.contacts.create!(name: 'Fora do Público', phone_number: '+5531987654321')

    create_campaign(message_body: 'Olá {{contact.name}}')
    campaign = WhatsappApiCampaign.find(response.parsed_body['id'])
    run_campaign(campaign)

    expect(outcome(campaign)).to eq([['Ana Souza', 'sent', nil], ['Bia Lima', 'sent', nil]])
  end

  # Consent per row: a contact whose row had only an e-mail never gets WhatsApp, even with a phone on file.
  it 'leaves out the contact whose row had no mobile, and skips everyone when the channel is turned off' do
    account.contacts.create!(name: 'Caio Reis', email: 'caio@gama.com.br', phone_number: '+5531987654321')
    content = "Nome,Celular,Email\nAna Souza,11987654321,\nCaio Reis,,caio@gama.com.br\n"
    mixed = saved_audience(account: account, user: user, content: content, mapping: { 'name' => 0, 'phone' => 1, 'email' => 2 })

    create_campaign(audience_id: mixed.id, message_body: 'Olá {{contact.first_name}}')
    expect(response.parsed_body['recipients_count']).to eq(1)
    campaign = WhatsappApiCampaign.find(response.parsed_body['id'])
    mixed.update!(channels: mixed.channels.merge('whatsapp' => { 'enabled' => false, 'count' => 1 }))
    run_campaign(campaign)

    expect(outcome(campaign)).to eq([['Ana Souza', 'cancelled', CampaignJourney::AudienceContacts::CHANNEL_DISABLED_REASON]])
    expect(Message.where(inbox: inbox).count).to eq(0)
  end

  # PRD §6.3: the audience's extra columns are tokens {{publico.<key>}} (normalized header).
  describe 'audience columns as tokens' do
    let(:audience) do
      content = "Nome,Celular,Data de Vencimento,Plano\nAna Souza,11987654321,10/2026,Ouro\nBia Lima,21987654321,,Prata\n"
      saved_audience(account: account, user: user, content: content)
    end
    let(:body) { 'Oi {{contact.first_name}}, plano {{publico.plano}} vence {{ publico.data_de_vencimento }}' }

    it 'fills each person from their row and skips who has no value with "falta <key>"' do
      create_campaign(message_body: body)

      expect(response).to have_http_status(:ok)
      campaign = WhatsappApiCampaign.find(response.parsed_body['id'])
      run_campaign(campaign)

      expect(outcome(campaign)).to eq([['Ana Souza', 'sent', nil], ['Bia Lima', 'cancelled', 'falta data_de_vencimento']])
      expect(Message.where(inbox: inbox).outgoing.pluck(:content)).to eq(['Oi Ana, plano Ouro vence 10/2026'])
    end

    # One-pass filling (an inserted value is never read again) is proven in template_renderer_spec.
    it 'uses the default text of the column, squished' do
      create_campaign(message_body: body, variable_defaults: { 'publico.data_de_vencimento' => "em\nbreve" })
      campaign = WhatsappApiCampaign.find(response.parsed_body['id'])
      expect(CampaignAudienceLink.for_campaign(campaign).variable_defaults).to eq('publico.data_de_vencimento' => 'em breve')
      run_campaign(campaign)

      expect(outcome(campaign).map(&:second)).to eq(%w[sent sent])
      expect(Message.where(inbox: inbox).outgoing.order(:id).pluck(:content)).to eq(
        ['Oi Ana, plano Ouro vence 10/2026', 'Oi Bia, plano Prata vence em breve']
      )
    end

    it 'refuses a column the audience does not have, and defaults for tokens the message does not use' do
      create_campaign(message_body: 'Oi {{publico.cpf}}')
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['code']).to eq('unknown_audience_column')

      create_campaign(message_body: body, variable_defaults: { 'publico.cpf' => 'x' })
      expect(response.parsed_body['code']).to eq('invalid_variable_defaults')
      expect(WhatsappApiCampaign.count).to eq(0)
    end

    it 'does not accept audience tokens outside the journey' do
      campaign = WhatsappApiCampaign.new(account: account, inbox: inbox, created_by: user, title: 'x', audience: [{ type: 'Label', id: 1 }],
                                         scheduled_at: Time.current, message_body: 'Oi {{publico.plano}}')
      expect(campaign).not_to be_valid
      expect(campaign.errors[:message_body].join).to include('publico.plano')
    end
  end

  # J4: the API refuses a channel the audience does not have.
  it 'refuses an audience without WhatsApp, or with WhatsApp off, with channel_not_in_audience' do
    emails_only = saved_audience(account: account, user: user, content: "Nome,Email\nAna,ana@alfa.com.br\n", mapping: { 'name' => 0, 'email' => 1 })
    create_campaign(audience_id: emails_only.id)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['code']).to eq('channel_not_in_audience')

    audience.update!(channels: audience.channels.merge('whatsapp' => { 'enabled' => false, 'count' => 2 }))
    create_campaign
    expect(response.parsed_body['code']).to eq('channel_not_in_audience')
    expect(WhatsappApiCampaign.count).to eq(0)
  end

  it 'refuses an inbox not marked for campaigns, unknown variables and a disabled feature' do
    create_campaign(inbox_id: create_whatsapp_api_inbox(account: account, enabled: false).id)
    expect(response.parsed_body['code']).to eq('whatsapp_api_inbox_required')

    create_campaign(message_body: 'Olá {{contact.cpf}}')
    expect(response.parsed_body['code']).to eq('unsupported_variables')

    create_campaign(title: '')
    expect(response.parsed_body['code']).to eq('invalid_campaign')

    allow(WhatsappApiCampaigns::Config).to receive(:enabled?).and_return(false)
    create_campaign
    expect(response.parsed_body['code']).to eq('channel_not_connected')
    expect(WhatsappApiCampaign.count).to eq(0)
    expect(CampaignAudienceLink.count).to eq(0)
  end
end
