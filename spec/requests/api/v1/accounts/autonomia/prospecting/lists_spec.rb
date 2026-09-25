require 'rails_helper'

RSpec.describe 'Autonomia prospecting lists API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:lead) { create_lead('Alpha Restaurante', 'mock-place-1') }
  let(:second_lead) { create_lead('Beta Clinica', 'mock-place-2') }

  before do
    Autonomia::Prospecting::Config.enable_for!(account)
  end

  it 'creates and shows a prospecting list' do
    post "/api/v1/accounts/#{account.id}/autonomia/prospecting/lists",
         params: { list: { name: 'Restaurantes BH', description: 'Outbound julho' } },
         headers: auth_headers(admin)

    expect(response).to have_http_status(:created)
    payload = response.parsed_body['payload']
    expect(payload['name']).to eq('Restaurantes BH')
    expect(payload['leads_count']).to eq(0)

    get "/api/v1/accounts/#{account.id}/autonomia/prospecting/lists/#{payload['id']}", headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('payload', 'leads')).to eq([])
  end

  it 'adds leads idempotently and removes them from a list' do
    list = create_list

    2.times do
      post "/api/v1/accounts/#{account.id}/autonomia/prospecting/lists/#{list.id}/leads",
           params: { lead_id: lead.id },
           headers: auth_headers(admin)
    end

    expect(response).to have_http_status(:ok)
    expect(list.list_leads.count).to eq(1)
    expect(response.parsed_body.dig('payload', 'lead_ids')).to eq([lead.id])
    expect(response.parsed_body.dig('payload', 'leads', 0, 'status')).to eq('ready_for_campaign')
    expect(lead.reload).to be_ready_for_campaign

    delete "/api/v1/accounts/#{account.id}/autonomia/prospecting/lists/#{list.id}/leads/#{lead.id}",
           headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('payload', 'lead_ids')).to eq([])
    expect(list.list_leads.reload).to be_empty
  end

  it 'filters leads by list' do
    list = create_list
    list.list_leads.create!(account: account, lead: lead)
    second_lead

    get "/api/v1/accounts/#{account.id}/autonomia/prospecting/leads",
        params: { list_id: list.id },
        headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    payload = response.parsed_body['payload']
    expect(payload.size).to eq(1)
    expect(payload.first['id']).to eq(lead.id)
  end

  it 'does not add leads from another account' do
    other_account = create(:account)
    other_lead = Autonomia::Prospecting::Lead.create!(
      account: other_account,
      provider: 'mock',
      provider_place_id: 'other-place',
      name: 'Outro Lead',
      dedupe_key: 'mock:other-place'
    )
    list = create_list

    post "/api/v1/accounts/#{account.id}/autonomia/prospecting/lists/#{list.id}/leads",
         params: { lead_id: other_lead.id },
         headers: auth_headers(admin)

    expect(response).to have_http_status(:not_found)
    expect(list.list_leads.count).to eq(0)
  end

  # A lista mostra o mesmo decisor da busca (#679): o da pesquisa. O nome que ficou gravado de antes (palpite da IA da
  # E2) continua no banco, mas não volta como decisor quando a pesquisa terminou sem dono.
  describe 'decisor dos leads da lista' do
    let(:profile) do
      Autonomia::Prospecting::CompanyProfile.create!(
        cnpj: '12345678000190', legal_name: 'ALPHA RESTAURANTE LTDA', verified_at: 1.day.ago,
        registration_status: 'ATIVA', registration_state: 'MG', owners: [], qsa: []
      )
    end

    def research(target, decision_status:, owners:, reason: nil)
      target.update!(company_profile: profile, company_research_status: 'confirmed', decision_research_status: decision_status,
                     metadata: { 'research' => { 'owners' => owners, 'no_decision_reason' => reason, 'decision_source' => 'qsa' } })
    end

    def listed_lead(target)
      list = create_list
      list.list_leads.create!(account: account, lead: target)
      get "/api/v1/accounts/#{account.id}/autonomia/prospecting/lists/#{list.id}", headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      response.parsed_body.dig('payload', 'leads', 0)
    end

    it 'pesquisa sem dono: o nome antigo da IA não volta como decisor e o motivo vem no bloco research' do
      lead.update!(decision_name: 'Joao Palpite IA', decision_role: 'Gerente')
      research(lead, decision_status: 'no_result', owners: [], reason: 'only_companies')

      payload = listed_lead(lead)

      expect(payload['research']).to include('decision_status' => 'no_result', 'no_decision_reason' => 'only_companies',
                                             'decision' => nil)
      expect(payload.dig('research', 'company', 'legal_name')).to eq('ALPHA RESTAURANTE LTDA')
    end

    it 'pesquisa com dono: o decisor vem da pesquisa' do
      lead.update!(decision_name: 'ANA SOUZA', decision_role: 'Sócio-Administrador', decision_confidence: 0.9)
      research(lead, decision_status: 'confirmed', owners: [{ 'name' => 'ANA SOUZA', 'qualification' => 'Sócio-Administrador' }])

      payload = listed_lead(lead)

      expect(payload.dig('research', 'decision')).to include('name' => 'ANA SOUZA', 'role' => 'Sócio-Administrador')
      expect(payload.dig('research', 'owners')).to eq([{ 'name' => 'ANA SOUZA', 'qualification' => 'Sócio-Administrador' }])
    end
  end

  it 'creates a campaign segment from leads ready for campaign' do
    list = create_list
    mark_ready_for_campaign(lead, phone: '+5531999990001')
    second_lead.update!(status: :qualified, phone: '+5531999990002')
    list.list_leads.create!(account: account, lead: lead)
    list.list_leads.create!(account: account, lead: second_lead)

    post "/api/v1/accounts/#{account.id}/autonomia/prospecting/lists/#{list.id}/campaign_segment",
         params: { campaign_segment: { segment_name: 'Restaurantes Divinopolis' } },
         headers: auth_headers(admin)

    expect(response).to have_http_status(:created)
    segment = response.parsed_body.dig('payload', 'segment')
    expect(segment['label']['title']).to start_with("prospeccao_#{list.id}_restaurantes_divinopolis")
    expect(segment['eligible_count']).to eq(1)
    expect(segment['blocked_count']).to eq(1)

    contact = lead.reload.contact
    expect(contact).to be_present
    expect(contact.label_list).to include(segment['label']['title'])
    expect(second_lead.reload.contact).to be_blank
    expect(response.parsed_body.dig('payload', 'list', 'campaign_segment', 'label_title')).to eq(segment['label']['title'])
  end

  it 'attaches the segment label to an existing campaign without sending it' do
    list = create_list
    mark_ready_for_campaign(lead, phone: '+5531999990001')
    list.list_leads.create!(account: account, lead: lead)
    campaign = create_sms_campaign

    post "/api/v1/accounts/#{account.id}/autonomia/prospecting/lists/#{list.id}/campaign_segment",
         params: { campaign_segment: { campaign_id: campaign.display_id, segment_name: 'Campanha restaurantes' } },
         headers: auth_headers(admin)

    expect(response).to have_http_status(:created)
    segment = response.parsed_body.dig('payload', 'segment')
    campaign.reload
    expect(campaign).to be_active
    expect(campaign.audience).to include('type' => 'Label', 'id' => segment.dig('label', 'id'))
    expect(segment.dig('campaign', 'id')).to eq(campaign.display_id)
  end

  it 'blocks campaign segment creation when no leads are ready for campaign' do
    list = create_list
    lead.update!(status: :qualified)
    list.list_leads.create!(account: account, lead: lead)

    post "/api/v1/accounts/#{account.id}/autonomia/prospecting/lists/#{list.id}/campaign_segment",
         headers: auth_headers(admin)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('prospecting.campaign.no_eligible_leads')
    expect(account.labels.where("title LIKE 'prospeccao_%'")).to be_empty
  end

  def create_list
    Autonomia::Prospecting::List.create!(account: account, user: admin, name: 'Lista teste')
  end

  # CampaignSegmentBuilder only treats a lead as eligible when it is ready_for_campaign
  # AND its phone was verified on WhatsApp (see Autonomia::Prospecting::WhatsappVerifier).
  def mark_ready_for_campaign(prospect_lead, phone:)
    prospect_lead.update!(
      status: :ready_for_campaign,
      phone: phone,
      metadata: prospect_lead.metadata.to_h.merge(
        'whatsapp_verification' => { 'status' => 'verified', 'phone' => phone }
      )
    )
  end

  def create_sms_campaign
    channel = create(:channel_sms, account: account)
    create(
      :campaign,
      account: account,
      inbox: channel.inbox,
      audience: [],
      scheduled_at: 1.day.from_now
    )
  end

  def create_lead(name, place_id)
    Autonomia::Prospecting::Lead.create!(
      account: account,
      provider: 'mock',
      provider_place_id: place_id,
      name: name,
      city: 'Belo Horizonte',
      state: 'MG',
      country: 'BR'
    )
  end

  def auth_headers(user)
    { 'api_access_token' => user.access_token.token }
  end
end
