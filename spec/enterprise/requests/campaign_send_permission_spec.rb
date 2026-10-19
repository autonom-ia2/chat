require 'rails_helper'

# #1898: campaign_send split from campaign_manage. Who only builds leaves the campaign ready; sending, scheduling and
# resuming need campaign_send. Lives under spec/enterprise: the custom-role half of permission_granted? is EE.
RSpec.describe 'Campaign send permission (#1898)', :aggregate_failures, type: :request do
  around do |example|
    with_modified_env(CAMPAIGN_JOURNEY_ENABLED: 'true', CRM_KANBAN_ENABLED: 'true', EMAIL_CAMPAIGN_ENABLED: 'true',
                      WHATSAPP_API_CAMPAIGNS_ENABLED: 'true') { example.run }
  end

  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:admin) { account_and_user.last }
  let(:builder) { agent_with(%w[campaign_manage]) }
  let(:sender) { agent_with(%w[campaign_manage campaign_send]) }

  def agent_with(permissions)
    user = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: permissions)
    user.account_users.find_by(account: account).update!(custom_role: role)
    user
  end

  def headers(user)
    { 'api_access_token' => user.access_token.token }
  end

  describe 'journey campaign (SMS sends right away)' do
    let!(:inbox) { journey_twilio_sms_inbox(account) }
    let(:audience) { saved_audience(account: account, user: admin, content: "Nome,Celular\nAna Souza,11987654321\n") }

    def create_sms(as:)
      post "/api/v1/accounts/#{account.id}/campaign_journey/campaigns",
           params: { campaign_import_id: audience.id, channel: 'sms',
                     campaign: { title: 'Parcela', inbox_id: inbox.id, scheduled_at: nil, message: 'Oi' } },
           headers: headers(as), as: :json
    end

    it 'refuses who only builds and creates nothing' do
      create_sms(as: builder)

      expect(response).to have_http_status(:unauthorized)
      expect(account.campaigns.count).to eq(0)
    end

    it 'lets who sends create it' do
      create_sms(as: sender)

      expect(response).to have_http_status(:ok)
      expect(account.campaigns.count).to eq(1)
    end
  end

  describe 'paused campaign' do
    let(:channel) { journey_cloud_channel(account) }
    let(:campaign) do
      create(:campaign, account: account, inbox: channel.inbox, title: 'Renovação', audience: [],
                        template_params: journey_template_params, message: 'Olá', scheduled_at: 1.hour.ago)
    end
    let!(:pause) do
      CampaignPauses::Pauser.new(campaign, source: 'template', reason_code: 'template_not_approved', details: {}).perform
    end

    def resume(as:)
      post "/api/v1/accounts/#{account.id}/campaign_journey/campaign_pauses/#{pause.id}/resume", headers: headers(as)
    end

    it 'refuses to resume for who only builds' do
      resume(as: builder)

      expect(response).to have_http_status(:unauthorized)
      expect(pause.reload.resumed_at).to be_nil
    end

    it 'resumes for who sends' do
      resume(as: sender)

      expect(response).to have_http_status(:ok)
      expect(pause.reload.resumed_at).to be_present
    end
  end

  describe 'e-mail campaign' do
    let(:campaign) { create(:email_campaign, account: account) }

    %w[send_now schedule resume].each do |action|
      it "refuses #{action} for who only builds and keeps the campaign as it was" do
        post "/api/v1/accounts/#{account.id}/email_campaigns/campaigns/#{campaign.id}/#{action}",
             params: { scheduled_at: 1.day.from_now.iso8601 }, headers: headers(builder), as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(campaign.reload).to be_draft
      end
    end

    it 'still lets who only builds edit the draft' do
      patch "/api/v1/accounts/#{account.id}/email_campaigns/campaigns/#{campaign.id}",
            params: { email_campaign: { name: 'Novidades' } }, headers: headers(builder), as: :json

      expect(response).to have_http_status(:ok)
      expect(campaign.reload.name).to eq('Novidades')
    end
  end

  describe 'WhatsApp API campaign (creating it sends)' do
    it 'refuses who only builds and creates nothing' do
      post "/api/v1/accounts/#{account.id}/whatsapp_api_campaigns",
           params: { title: 'Oferta', message_body: 'Oi' }, headers: headers(builder), as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(account.whatsapp_api_campaigns.count).to eq(0)
    end
  end

  describe 'classic campaign' do
    let(:inbox) { create(:inbox, account: account) }

    def create_classic(as:, **attrs)
      post "/api/v1/accounts/#{account.id}/campaigns",
           params: { campaign: { title: 'Aviso', message: 'Oi', inbox_id: inbox.id }.merge(attrs) }, headers: headers(as), as: :json
    end

    it 'refuses a scheduled campaign for who only builds' do
      create_classic(as: builder, scheduled_at: 1.day.from_now.iso8601)

      expect(response).to have_http_status(:unauthorized)
      expect(account.campaigns.count).to eq(0)
    end

    it 'refuses scheduling an existing campaign for who only builds' do
      campaign = create(:campaign, account: account, inbox: inbox)

      patch "/api/v1/accounts/#{account.id}/campaigns/#{campaign.display_id}",
            params: { campaign: { scheduled_at: 1.day.from_now.iso8601 } }, headers: headers(builder), as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(campaign.reload.scheduled_at).to be_nil
    end

    it 'lets who only builds create a campaign that is not scheduled' do
      create_classic(as: builder)

      expect(response).to have_http_status(:ok)
    end

    it 'lets who sends schedule it' do
      create_classic(as: sender, scheduled_at: 1.day.from_now.iso8601)

      expect(response).to have_http_status(:ok)
    end
  end
end
