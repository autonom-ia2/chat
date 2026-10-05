require 'rails_helper'

# #993: what Novo público and Nova campanha read from an audience — problem rows (B5), the first
# contact for the preview, masked column examples, saved audiences with search and who does not
# receive (B8).
RSpec.describe 'Audience preview endpoints (#993)', :aggregate_failures, type: :request do
  around do |example|
    with_modified_env(CAMPAIGN_IMPORT_ENABLED: 'true') { example.run }
  end

  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  let(:content) do
    "Nome,Celular,Email,Empresa,Vencimento\n" \
      "Ana Souza,11987654321,ana@alfa.com.br,Alfa,10/2026\n" \
      "Bia Lima,123,,Beta,\n" \
      "Caio Reis,31987654321,caio@gama.com.br,Gama,12/2026\n"
  end
  let(:audience) do
    saved_audience(account: account, user: user, content: content,
                   mapping: { 'name' => 0, 'phone' => 1, 'email' => 2, 'company' => 3 })
  end

  def headers_for(member = user)
    { 'api_access_token' => member.access_token.token }
  end

  def agent_with(permissions)
    agent = User.create!(name: 'Agente', email: "agente-#{SecureRandom.hex(4)}@example.com", password: 'Passw0rd!23', confirmed_at: Time.current)
    AccountUser.create!(account: account, user: agent, role: :agent, custom_role: create(:custom_role, account: account, permissions: permissions))
    agent
  end

  def audience_url(path = '')
    "/api/v1/accounts/#{account.id}/campaign_imports/#{audience.id}#{path}"
  end

  describe 'GET problem_rows (B5)' do
    it 'lists the rows left out with the reason and a masked contact, never the name' do
      get audience_url('/problem_rows'), headers: headers_for(agent_with(['campaign_view']))

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['meta']).to eq('count' => 1, 'page' => 1, 'per_page' => 50)
      row = body['payload'].sole
      expect(row['row_number']).to eq(3)
      expect(row['errors']).to eq(['invalid_brazilian_mobile_number'])
      expect(row.keys).to contain_exactly('row_number', 'contact_masked', 'errors')
      expect(response.body).not_to include('Bia')
      expect(response.body).not_to include('Lima')
    end

    it 'pages the rows' do
      get audience_url('/problem_rows'), params: { page: 2 }, headers: headers_for

      expect(response.parsed_body['payload']).to eq([])
      expect(response.parsed_body.dig('meta', 'page')).to eq(2)
    end
  end

  describe 'GET sample_contact' do
    it 'returns the first eligible person of this audience for the preview' do
      get audience_url('/sample_contact'), headers: headers_for

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['payload']).to include(
        'name' => 'Ana Souza', 'first_name' => 'Ana', 'extra_values' => { 'Vencimento' => '10/2026' }
      )
      expect(response.parsed_body.dig('payload', 'company_name')).to be_present
    end

    it 'needs campaign_manage' do
      get audience_url('/sample_contact'), headers: headers_for(agent_with(['campaign_view']))

      expect(response).to have_http_status(:unauthorized)
    end

    it 'never reads an audience of another account' do
      other_account, other_user = create_account_and_user
      other = saved_audience(account: other_account, user: other_user, content: content,
                             mapping: { 'name' => 0, 'phone' => 1, 'email' => 2, 'company' => 3 })

      get "/api/v1/accounts/#{account.id}/campaign_imports/#{other.id}/sample_contact", headers: headers_for

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET show' do
    it 'adds a masked example per column (the Jev format, never a value) and who does not receive (B8)' do
      audience.campaign_import_rows.order(:row_number).first.contact.opt_out!(source: 'manual')
      EmailSuppression.create!(account: account, email: 'caio@gama.com.br', reason: 'unsubscribe', source: 'manual')

      get audience_url, headers: headers_for

      payload = response.parsed_body['payload']
      examples = payload.dig('schema_resolution', 'columns').pluck('header', 'example_masked')
      expect(examples).to include(['Nome', 'Aaa Aaaaa'], ['Email', '[email address]'])
      expect(response.body).not_to include('ana@alfa.com.br')
      expect(payload.dig('reachability', 'whatsapp')).to include('total' => 2, 'opted_out' => 1, 'receive' => 1)
      expect(payload.dig('reachability', 'email')).to include('total' => 2, 'unsubscribed' => 1, 'receive' => 1)
    end
  end

  describe 'GET index with saved and q (Passo 1)' do
    it 'lists only saved audiences and searches the name' do
      audience.update!(name: 'Corretoras parceiras')
      pending_import = create_audience_import(account: account, user: user, content: content)
      pending_import.update!(name: 'Corretoras em leitura', status: :ready_to_confirm)

      get "/api/v1/accounts/#{account.id}/campaign_imports", params: { saved: true, q: 'parceiras' }, headers: headers_for

      expect(response.parsed_body['payload'].pluck('id')).to eq([audience.id])
      expect(response.parsed_body.dig('meta', 'count')).to eq(1)

      get "/api/v1/accounts/#{account.id}/campaign_imports", params: { q: 'corretoras' }, headers: headers_for
      expect(response.parsed_body['payload'].pluck('id')).to contain_exactly(audience.id, pending_import.id)

      get "/api/v1/accounts/#{account.id}/campaign_imports", params: { q: '%' }, headers: headers_for
      expect(response.parsed_body['payload']).to eq([])
    end
  end

  describe 'side panel (PRD §6.6)' do
    it 'lists the contacts saved by the audience, paged, for campaign_view' do
      get audience_url('/contacts'), headers: headers_for(agent_with(['campaign_view']))

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['payload'].pluck('name')).to eq(['Ana Souza', 'Caio Reis'])
      expect(response.parsed_body['meta']).to eq('count' => 2, 'page' => 1, 'per_page' => 25)
      expect(response.parsed_body['payload'].first.keys).to contain_exactly('id', 'name', 'email', 'phone_number', 'company_name')
    end

    it 'shows the campaigns that used the audience, old ones linked by the backfill included (F1)' do
      channel = journey_cloud_channel(account)
      campaign = create(:campaign, account: account, inbox: channel.inbox, title: 'Renovação outubro', audience: [],
                                   template_params: journey_template_params)
      CampaignAudienceLink.create!(account: account, campaign: campaign, campaign_import: audience)

      get audience_url, headers: headers_for

      expect(response.parsed_body.dig('payload', 'linked_campaigns')).to eq(
        [{ 'type' => 'Campaign', 'id' => campaign.id, 'title' => 'Renovação outubro', 'channel' => 'whatsapp_official',
           'status' => 'active' }]
      )
    end

    it 'old imports keep the original campaign name and list their contacts (F1)' do
      old = create_campaign_import(account: account, user: user, content: "nome,celular\nAna,11987654321\n", batch_count: 1,
                                   filename: 'base.csv', content_type: 'text/csv')
      old.update!(campaign_name: 'Base de setembro')

      get "/api/v1/accounts/#{account.id}/campaign_imports/#{old.id}", headers: headers_for
      expect(response.parsed_body.dig('payload', 'campaign_name')).to eq('Base de setembro')
      expect(response.parsed_body.dig('payload', 'name')).to be_nil

      get "/api/v1/accounts/#{account.id}/campaign_imports/#{old.id}/contacts", headers: headers_for
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['payload']).to eq([])
    end
  end
end
