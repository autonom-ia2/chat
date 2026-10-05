require 'rails_helper'

# #1007 — result of one campaign (PRD §6.5, O1–O2, E1, E3, E4) for every channel of the journey.
# Contract in docs/campaigns/publicos/resultado-1007.md.
RSpec.describe 'Campaign journey results API (#1007)', :aggregate_failures, type: :request do
  around do |example|
    with_modified_env(CAMPAIGN_JOURNEY_ENABLED: 'true', EMAIL_CAMPAIGN_ENABLED: 'true', CRM_KANBAN_ENABLED: 'true') { example.run }
  end

  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:admin) { account_and_user.last }
  let(:reply_inbox) { create_crm_inbox(account: account, members: [admin]) }
  let(:whatsapp_inbox) { create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false).inbox }
  let(:whatsapp_campaign) do
    create(:campaign, account: account, inbox: whatsapp_inbox, title: 'Renovação auto', campaign_type: :one_off,
                      template_params: { 'name' => 'renovacao_auto_v2' })
  end
  let(:ana) { account.contacts.create!(name: 'Ana Maria Souza', phone_number: '+5511987654321', email: 'ana@alfa.com.br') }
  let(:bia) { account.contacts.create!(name: 'Bia Lima', phone_number: '+5521987654322') }
  let(:caio) { account.contacts.create!(name: 'Caio', phone_number: '+5531987654323') }
  let(:duda) { account.contacts.create!(name: 'Duda Reis', phone_number: '+5541987654324') }

  def headers(user = admin)
    { 'api_access_token' => user.access_token.token }
  end

  def result_path(channel, id, suffix = '')
    "/api/v1/accounts/#{account.id}/campaign_journey/results/#{channel}/#{id}#{suffix}"
  end

  def campaign_recipient(campaign, contact, status, **attributes)
    CampaignRecipient.create!(account: account, campaign: campaign, contact: contact, inbox: campaign.inbox, status: status, **attributes)
  end

  def replied!(contact, campaign)
    conversation = create_crm_conversation(account: account, inbox: reply_inbox, contact: contact)
    CampaignJourney::CampaignMarks.mark!(conversation, campaign)
    conversation
  end

  def viewer
    user = User.create!(name: 'Leitor', email: "leitor-#{SecureRandom.hex(4)}@example.com", password: 'Passw0rd!23', confirmed_at: Time.current)
    view_only = create(:custom_role, account: account, permissions: %w[campaign_view])
    AccountUser.create!(account: account, user: user, role: :agent, custom_role: view_only)
    user
  end

  describe 'WhatsApp Oficial' do
    before do
      campaign_recipient(whatsapp_campaign, ana, :read, source_id: 'wamid.1', sent_at: 1.hour.ago, message_content: 'Olá Ana')
      campaign_recipient(whatsapp_campaign, bia, :delivered, source_id: 'wamid.2', sent_at: 1.hour.ago)
      campaign_recipient(whatsapp_campaign, caio, :failed, error_code: '131026', error_title: 'Número sem WhatsApp')
      campaign_recipient(whatsapp_campaign, duda, :skipped, error_message: 'falta {{2}}')
    end

    it 'returns the numbers of the campaign with E1 holding and Responderam from the CRM mark' do
      replied!(ana, whatsapp_campaign)

      get result_path('whatsapp_official', whatsapp_campaign.display_id), headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      payload = response.parsed_body['payload']
      totals = payload['totals']
      expect(totals).to include('audience' => 4, 'sent' => 2, 'delivered' => 2, 'read' => 1, 'failed' => 1, 'skipped' => 1,
                                'queued' => 0, 'replied' => 1)
      expect(totals.values_at('sent', 'failed', 'skipped', 'queued').sum).to eq(totals['audience'])
      expect(payload['campaign']).to include('channel' => 'whatsapp_official', 'name' => 'Renovação auto', 'template_name' => 'renovacao_auto_v2')
      expect(payload['crm']).to eq('source_id' => "campaign:whatsapp:#{whatsapp_campaign.id}", 'enabled' => true)
    end

    it 'lists people with masked phone, reason and the conversation of who replied (E3)' do
      conversation = replied!(ana, whatsapp_campaign)

      get result_path('whatsapp_official', whatsapp_campaign.display_id, '/recipients'), headers: headers, as: :json

      rows = response.parsed_body.dig('payload', 'rows')
      expect(rows.size).to eq(4)
      ana_row = rows.find { |row| row.dig('contact', 'id') == ana.id }
      expect(ana_row).to include('status' => 'read', 'message_content' => 'Olá Ana', 'conversation_display_id' => conversation.display_id)
      expect(ana_row.dig('contact', 'phone_number')).not_to include('987654321')
      expect(rows.find { |row| row.dig('contact', 'id') == caio.id }).to include('error_code' => '131026', 'conversation_display_id' => nil)
    end

    it 'filters by situation, "sent" counting delivered and read like the number above' do
      replied!(ana, whatsapp_campaign)

      statuses = %w[sent replied failed].index_with do |status|
        get result_path('whatsapp_official', whatsapp_campaign.display_id, '/recipients'), params: { status: status }, headers: headers
        response.parsed_body.dig('payload', 'rows').map { |row| row.dig('contact', 'name') }.sort
      end

      expect(statuses).to eq('sent' => ['Ana Maria Souza', 'Bia Lima'], 'replied' => ['Ana Maria Souza'], 'failed' => ['Caio'])
    end

    it 'refuses an unknown filter' do
      get result_path('whatsapp_official', whatsapp_campaign.display_id, '/recipients'), params: { status: 'opened' }, headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'hides "Abrir conversa" of a conversation the agent cannot see' do
      replied!(ana, whatsapp_campaign)

      get result_path('whatsapp_official', whatsapp_campaign.display_id, '/recipients'), params: { status: 'replied' }, headers: headers(viewer)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('payload', 'rows').first['conversation_display_id']).to be_nil
    end

    it 'exports the result masked (E4)' do
      replied!(ana, whatsapp_campaign)

      get result_path('whatsapp_official', whatsapp_campaign.display_id, '/export'), headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.headers['Content-Type']).to include('text/csv')
      csv = CSV.parse(response.body.delete_prefix("\uFEFF"), headers: true)
      expect(csv.headers).to eq(CampaignJourney::ResultExport::MESSAGE_COLUMNS.map(&:to_s))
      ana_line = csv.find { |line| line['name'] == 'Ana S.' }
      expect(ana_line.to_h).to include('status' => 'read', 'replied' => 'true')
      expect(response.body).not_to include('987654321')
      expect(response.body).not_to include('Souza')
      expect(csv.find { |line| line['name'] == 'Caio' }['reason']).to eq('Número sem WhatsApp')
    end

    it 'exports only the filtered situation' do
      get result_path('whatsapp_official', whatsapp_campaign.display_id, '/export'), params: { status: 'failed' }, headers: headers

      expect(CSV.parse(response.body.delete_prefix("\uFEFF"), headers: true).map { |line| line['name'] }).to eq(['Caio'])
    end
  end

  describe 'permissions and scoping' do
    it 'lets campaign_view read but not export (A4)' do
      user = viewer

      get result_path('whatsapp_official', whatsapp_campaign.display_id), headers: headers(user), as: :json
      expect(response).to have_http_status(:ok)

      get result_path('whatsapp_official', whatsapp_campaign.display_id, '/export'), headers: headers(user)
      expect(response).to have_http_status(:unauthorized)
    end

    it 'answers 401 to an agent without campaign permissions' do
      agent, = create_crm_agent(account: account)

      get result_path('whatsapp_official', whatsapp_campaign.display_id), headers: headers(agent), as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'never shows a campaign of another account or under another channel' do
      other_account, = create_account_and_user
      other = create(:email_campaign, account: other_account)

      get result_path('email', other.id), headers: headers, as: :json
      expect(response).to have_http_status(:not_found)

      get result_path('sms', whatsapp_campaign.display_id), headers: headers, as: :json
      expect(response).to have_http_status(:not_found)

      get result_path('telegram', whatsapp_campaign.display_id), headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it 'answers 404 when CAMPAIGN_JOURNEY_ENABLED is off' do
      with_modified_env(CAMPAIGN_JOURNEY_ENABLED: 'false') do
        get result_path('whatsapp_official', whatsapp_campaign.display_id), headers: headers, as: :json
      end

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'SMS' do
    let(:sms_campaign) do
      create(:campaign, account: account, inbox: create(:channel_sms, account: account).inbox, title: 'Lembrete de parcela', campaign_type: :one_off)
    end

    it 'reads campaign_recipients when they exist, without "Lidas"' do
      campaign_recipient(sms_campaign, ana, :delivered, source_id: 'sms-1', sent_at: 1.hour.ago)
      campaign_recipient(sms_campaign, bia, :failed, error_message: 'Número inválido na operadora')

      get result_path('sms', sms_campaign.display_id), headers: headers, as: :json

      expect(response.parsed_body.dig('payload', 'totals')).to include('audience' => 2, 'sent' => 1, 'delivered' => 1, 'read' => nil, 'failed' => 1)
      expect(response.parsed_body.dig('payload', 'filters')).not_to include('read')
    end

    it 'answers zeros while the SMS engine records nobody (#1004 pending)' do
      get result_path('sms', sms_campaign.display_id), headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('payload', 'totals')).to include('audience' => 0, 'sent' => 0)
    end
  end

  describe 'WhatsApp API' do
    let(:api_inbox) { create_crm_whatsapp_api_inbox(account: account) }
    let(:api_campaign) do
      WhatsappApiCampaign.create!(account: account, inbox: api_inbox, created_by: admin, title: 'Lembrete de vistoria',
                                  audience: [{ 'type' => 'Label', 'id' => 1 }], message_body: 'Olá', scheduled_at: 1.hour.ago, status: :completed)
    end

    def api_recipient(contact, status, **attributes)
      api_campaign.whatsapp_api_campaign_recipients.create!(account: account, inbox: api_inbox, contact: contact, status: status, **attributes)
    end

    it 'maps the engine statuses and keeps E1 (no delivery or read receipt)' do
      api_recipient(ana, :sent, sent_at: 1.hour.ago)
      api_recipient(bia, :failed, last_error_message: 'timeout')
      api_recipient(caio, :cancelled, last_error_message: 'opted_out')
      api_recipient(duda, :pending)
      replied!(ana, api_campaign)

      get result_path('whatsapp_api', api_campaign.id), headers: headers, as: :json

      totals = response.parsed_body.dig('payload', 'totals')
      expect(totals).to include('audience' => 4, 'sent' => 1, 'failed' => 1, 'skipped' => 1, 'queued' => 1, 'delivered' => nil,
                                'read' => nil, 'replied' => 1)
      expect(totals.values_at('sent', 'failed', 'skipped', 'queued').sum).to eq(totals['audience'])

      get result_path('whatsapp_api', api_campaign.id, '/recipients'), params: { status: 'skipped' }, headers: headers
      expect(response.parsed_body.dig('payload', 'rows').map { |row| [row['status'], row['error_message']] }).to eq([%w[skipped opted_out]])
    end
  end

  describe 'E-mail' do
    let(:email_campaign) { create(:email_campaign, account: account, name: 'Novidades de outubro', status: :sent) }

    before do
      create(:email_campaign_recipient, email_campaign: email_campaign, email: 'ana@alfa.com.br', name: 'Ana Maria Souza',
                                        contact: ana, status: :delivered, sent_at: 1.hour.ago)
      create(:email_campaign_recipient, email_campaign: email_campaign, email: 'bia@beta.com', name: 'Bia Lima', status: :bounced,
                                        sent_at: 1.hour.ago)
      create(:email_campaign_recipient, email_campaign: email_campaign, email: 'caio@gama.com', name: 'Caio', status: :suppressed)
    end

    it 'adds Responderam to the E1 groups of the e-mail' do
      replied!(ana, email_campaign)

      get result_path('email', email_campaign.id), headers: headers, as: :json

      totals = response.parsed_body.dig('payload', 'totals')
      expect(totals).to eq('eligible' => 3, 'delivered' => 1, 'bounced' => 1, 'not_sent' => 1, 'replied' => 1)
      expect(totals.values_at('delivered', 'bounced', 'not_sent').sum).to eq(totals['eligible'])
      expect(response.parsed_body.dig('payload', 'crm', 'source_id')).to eq("campaign:email:#{email_campaign.id}")
    end

    it 'lists who replied with the conversation to open' do
      conversation = replied!(ana, email_campaign)

      get result_path('email', email_campaign.id, '/recipients'), params: { status: 'replied' }, headers: headers

      row = response.parsed_body.dig('payload', 'rows').sole
      expect(row).to include('conversation_display_id' => conversation.display_id, 'status' => 'replied')
      expect(row.dig('contact', 'email')).to eq('a**@alfa.com.br')
    end

    it 'exports masked e-mails and names' do
      get result_path('email', email_campaign.id, '/export'), headers: headers

      csv = CSV.parse(response.body.delete_prefix("\uFEFF"), headers: true)
      expect(csv.headers).to eq(CampaignJourney::ResultExport::EMAIL_COLUMNS.map(&:to_s))
      expect(csv.map { |line| [line['name'], line['email'], line['status']] }).to contain_exactly(
        ['Ana S.', 'a**@alfa.com.br', 'delivered'], ['Bia L.', 'b**@beta.com', 'bounced'], ['Caio', 'c***@gama.com', 'suppressed']
      )
    end
  end
end
