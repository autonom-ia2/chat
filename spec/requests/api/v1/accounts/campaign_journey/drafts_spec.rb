require 'rails_helper'

# #1898: rascunho da "Nova campanha" no servidor — quem só monta deixa pronta, quem dispara abre pela lista.
RSpec.describe 'Campaign journey drafts API (#1898)', :aggregate_failures, type: :request do
  around do |example|
    with_modified_env(CAMPAIGN_JOURNEY_ENABLED: 'true') { example.run }
  end

  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:admin) { account_and_user.last }
  let(:path) { "/api/v1/accounts/#{account.id}/campaign_journey/drafts" }
  let(:choices) { { 'version' => 1, 'audienceId' => 7, 'channel' => 'sms', 'inboxId' => 3, 'messageBody' => 'Oi', 'step' => 3 } }

  def headers(user = admin)
    { 'api_access_token' => user.access_token.token }
  end

  def create_draft(draft = { title: 'Parcela outubro', channel: 'sms', payload: choices }, user: admin)
    post path, params: { draft: draft }, headers: headers(user), as: :json
  end

  it 'saves the choices, lists the newest first with the author, opens, changes and removes the draft' do
    create_draft
    expect(response).to have_http_status(:created)
    first = response.parsed_body['payload']
    expect(first).to include('title' => 'Parcela outubro', 'channel' => 'sms', 'payload' => choices, 'email_campaign_id' => nil)
    expect(first['author']).to eq('id' => admin.id, 'name' => admin.name)

    travel 1.minute do
      create_draft({ title: 'Renovação', channel: 'whatsapp_api', payload: {} })
    end
    get path, headers: headers
    expect(response.parsed_body['payload'].pluck('title')).to eq(['Renovação', 'Parcela outubro'])

    patch "#{path}/#{first['id']}", params: { draft: { title: 'Parcela novembro', payload: choices.merge('step' => 2) } },
                                    headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    get "#{path}/#{first['id']}", headers: headers
    expect(response.parsed_body['payload']).to include('title' => 'Parcela novembro', 'payload' => choices.merge('step' => 2))

    delete "#{path}/#{first['id']}", headers: headers
    expect(response).to have_http_status(:no_content)
    expect(CampaignJourneyDraft.where(id: first['id'])).to be_empty
  end

  it 'refuses a channel the journey does not have and a payload that is not an object or too big' do
    create_draft({ title: 'X', channel: 'live_chat', payload: {} })
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['code']).to eq('draft_invalid')

    create_draft({ title: 'X', channel: 'sms', payload: { 'texto' => 'a' * CampaignJourneyDraft::MAX_PAYLOAD_BYTES } })
    expect(response).to have_http_status(:unprocessable_entity)

    create_draft({ title: 'X', channel: 'sms', payload: ['lista'] })
    expect(response).to have_http_status(:unprocessable_entity)
    create_draft({ title: 'X', channel: 'sms', payload: 'texto' })
    expect(response).to have_http_status(:unprocessable_entity)

    expect(CampaignJourneyDraft.new(account: account, payload: ['lista']).tap(&:valid?).errors[:payload]).to be_present
    expect(CampaignJourneyDraft.count).to eq(0)
  end

  it 'refuses an e-mail campaign that does not exist with 422, not 500' do
    create_draft({ title: 'E-mail', channel: 'email', email_campaign_id: 0, payload: {} })

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'only links an e-mail campaign of the same account' do
    foreign = create(:email_campaign)
    create_draft({ title: 'E-mail', channel: 'email', email_campaign_id: foreign.id, payload: {} })

    expect(response).to have_http_status(:unprocessable_entity)
    expect(CampaignJourneyDraft.count).to eq(0)
  end

  it 'keeps drafts of other accounts out of reach' do
    other = CampaignJourneyDraft.create!(account: create(:account), title: 'De outra conta')

    get path, headers: headers
    expect(response.parsed_body['payload']).to be_empty
    get "#{path}/#{other.id}", headers: headers
    expect(response).to have_http_status(:not_found)
    delete "#{path}/#{other.id}", headers: headers
    expect(response).to have_http_status(:not_found)
    expect(other.reload).to be_present
  end

  it 'hides an e-mail draft once that e-mail left the draft status' do
    email = create(:email_campaign, account: account, status: :draft)
    CampaignJourneyDraft.create!(account: account, user: admin, title: 'E-mail', channel: 'email', email_campaign: email)

    get path, headers: headers
    expect(response.parsed_body['payload'].size).to eq(1)

    email.update_columns(status: EmailCampaign.statuses[:scheduled]) # rubocop:disable Rails/SkipsModelValidations
    get path, headers: headers
    expect(response.parsed_body['payload']).to be_empty
  end

  it 'answers 404 with the journey off and 401 to an agent without campaign access' do
    with_modified_env(CAMPAIGN_JOURNEY_ENABLED: 'false') do
      get path, headers: headers
      expect(response).to have_http_status(:not_found)
    end

    agent = create(:user, account: account, role: :agent)
    get path, headers: headers(agent)
    expect(response).to have_http_status(:unauthorized)
    create_draft(user: agent)
    expect(response).to have_http_status(:unauthorized)
  end

  describe 'dispatch' do
    include CampaignJourneySmsHelpers

    let!(:inbox) { journey_twilio_sms_inbox(account) }
    let(:audience) { saved_audience(account: account, user: admin, content: "Nome,Celular\nAna Souza,11987654321\n") }

    def dispatch_sms(draft_id)
      post "/api/v1/accounts/#{account.id}/campaign_journey/campaigns",
           params: { campaign_import_id: audience.id, channel: 'sms', draft_id: draft_id,
                     campaign: { title: 'Parcela outubro', inbox_id: inbox.id, scheduled_at: nil, message: 'Oi' } },
           headers: headers, as: :json
    end

    it 'removes the draft the campaign came from, and only that one' do
      draft = CampaignJourneyDraft.create!(account: account, user: admin, title: 'Parcela outubro', channel: 'sms')
      other = CampaignJourneyDraft.create!(account: account, user: admin, title: 'Outra', channel: 'sms')
      foreign = CampaignJourneyDraft.create!(account: create(:account), title: 'De outra conta')

      dispatch_sms(draft.id)
      expect(response).to have_http_status(:ok)
      expect(CampaignJourneyDraft.where(id: draft.id)).to be_empty
      expect(other.reload).to be_present

      dispatch_sms(foreign.id)
      expect(response).to have_http_status(:ok)
      expect(foreign.reload).to be_present
    end

    it 'removes the e-mail draft when that e-mail is sent or scheduled' do
      email_env = { CRM_KANBAN_ENABLED: 'true', EMAIL_CAMPAIGN_ENABLED: 'true', EMAIL_REPUTATION_MODE: 'shadow',
                    EMAIL_CAMPAIGN_HYGIENE_MODE: 'shadow', EMAIL_REPUTATION_PROVIDER_MONITOR: 'false', EMAIL_REPUTATION_PROVIDER_BLOCK: 'false' }
      sent = create(:email_campaign, account: account, status: :draft)
      scheduled = create(:email_campaign, account: account, sender_identity: sent.sender_identity, status: :draft)
      [sent, scheduled].each do |email|
        create(:email_campaign_recipient, email_campaign: email)
        CampaignJourneyDraft.create!(account: account, user: admin, title: email.name, channel: 'email', email_campaign: email)
      end

      with_modified_env(**email_env) do
        post "/api/v1/accounts/#{account.id}/email_campaigns/campaigns/#{sent.id}/send_now", headers: headers, as: :json
        expect(response).to have_http_status(:ok)
        post "/api/v1/accounts/#{account.id}/email_campaigns/campaigns/#{scheduled.id}/schedule",
             params: { scheduled_at: 1.day.from_now.iso8601 }, headers: headers, as: :json
        expect(response).to have_http_status(:ok)
      end

      expect(CampaignJourneyDraft.where(account_id: account.id)).to be_empty
    end

    it 'ignores a draft_id that is a list, so one dispatch never removes several drafts' do
      drafts = Array.new(2) { |i| CampaignJourneyDraft.create!(account: account, user: admin, title: "R#{i}", channel: 'sms') }

      dispatch_sms(drafts.map(&:id))

      expect(response).to have_http_status(:ok)
      expect(CampaignJourneyDraft.where(id: drafts.map(&:id)).count).to eq(2)
    end

    it 'links the draft to the e-mail the journey creates, instead of removing it' do
      allow(EmailCampaigns::Config).to receive(:enabled?).and_return(true)
      allow(EmailCampaigns::RecipientPreflightJob).to receive(:enqueue)
      draft = CampaignJourneyDraft.create!(account: account, user: admin, title: 'Boletim', channel: 'email')
      identity = create(:email_sender_identity, account: account, domain: 'empresa.com.br', from_email: 'ola@empresa.com.br')
      with_email = saved_audience(account: account, user: admin, content: "Nome,Celular,Email\nAna Souza,11987654321,ana@cliente.com.br\n",
                                  mapping: { 'name' => 0, 'phone' => 1, 'email' => 2 })
      campaign = { title: 'Boletim', delivery_mode: 'ses', sender_identity_id: identity.id, from_name: 'Empresa', from_email: 'ola@empresa.com.br' }

      with_modified_env(EMAIL_CAMPAIGN_HYGIENE_MODE: 'shadow', EMAIL_REPUTATION_MODE: 'shadow', EMAIL_REPUTATION_PROVIDER_MONITOR: 'false',
                        EMAIL_REPUTATION_PROVIDER_BLOCK: 'false', EMAIL_REPUTATION_AWS_ACCOUNT_ID: '') do
        post "/api/v1/accounts/#{account.id}/campaign_journey/campaigns",
             params: { campaign_import_id: with_email.id, channel: 'email', draft_id: draft.id, campaign: campaign }, headers: headers, as: :json
      end

      expect(response).to have_http_status(:ok)
      expect(draft.reload.email_campaign_id).to eq(response.parsed_body['id'])
    end

    it 'keeps the draft when the campaign is refused' do
      draft = CampaignJourneyDraft.create!(account: account, user: admin, title: 'Parcela outubro', channel: 'sms')

      post "/api/v1/accounts/#{account.id}/campaign_journey/campaigns",
           params: { campaign_import_id: audience.id, channel: 'sms', draft_id: draft.id,
                     campaign: { title: 'Parcela outubro', inbox_id: 0, message: 'Oi' } },
           headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(draft.reload).to be_present
    end
  end
end
