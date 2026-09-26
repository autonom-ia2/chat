require 'rails_helper'

# "Adicionar à campanha" com a campanha da API do WhatsApp (#732, item 11; ACAO-X09), pela seleção da busca e pelas
# Listas. A permissão é a mesma da campanha de envio único: campaign_manage.
RSpec.describe 'Autonomia prospecting WhatsApp API campaign', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:base_url) { "/api/v1/accounts/#{account.id}/autonomia/prospecting" }
  let(:inbox) { create_whatsapp_api_inbox(account: account) }
  let(:campaign) do
    create_whatsapp_api_campaign(account: account, user: admin, inbox: inbox, label: account.labels.create!(title: 'base'))
  end

  around do |example|
    with_modified_env('WHATSAPP_API_CAMPAIGNS_ENABLED' => 'true') { example.run }
  end

  before { Autonomia::Prospecting::Config.enable_for!(account) }

  def create_lead(index)
    Autonomia::Prospecting::Lead.create!(
      account: account, provider: 'mock', provider_place_id: "place-wa-#{index}", name: "Empresa #{index}",
      phone: "+55 31 99999-000#{index}", country: 'BR', status: :ready_for_campaign,
      metadata: { 'whatsapp_verification' => { 'status' => 'verified', 'phone' => "+55 31 99999-000#{index}" } }
    )
  end

  def label_ids(target)
    target.reload.audience.map { |item| item.to_h.stringify_keys['id'] }
  end

  it 'a seleção da busca entra na campanha da API e a resposta diz o tipo' do
    post "#{base_url}/leads/campaign_segment",
         params: { lead_ids: [create_lead(1).id], campaign_id: campaign.id, campaign_type: 'whatsapp_api', segment_name: 'Seleção' },
         headers: auth_headers(admin), as: :json

    expect(response).to have_http_status(:created)
    segment = response.parsed_body.dig('payload', 'segment')
    expect(segment['campaign']).to eq('id' => campaign.id, 'title' => campaign.title, 'type' => 'whatsapp_api')
    expect(label_ids(campaign)).to include(segment.dig('label', 'id'))
  end

  it 'a lista entra na campanha da API' do
    list = Autonomia::Prospecting::List.create!(account: account, user: admin, name: 'Lista')
    list.list_leads.create!(account: account, lead: create_lead(2))

    post "#{base_url}/lists/#{list.id}/campaign_segment",
         params: { campaign_segment: { campaign_id: campaign.id, campaign_type: 'whatsapp_api', segment_name: 'Lista' } },
         headers: auth_headers(admin), as: :json

    expect(response).to have_http_status(:created)
    expect(response.parsed_body.dig('payload', 'segment', 'campaign', 'type')).to eq('whatsapp_api')
    expect(response.parsed_body.dig('payload', 'list', 'campaign_segment', 'campaign_type')).to eq('whatsapp_api')
  end

  it 'sem campaign_manage responde 403 e a audiência não muda' do
    agent = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: ['prospecting_manage'])
    agent.account_users.find_by(account: account).update!(custom_role: role)

    post "#{base_url}/leads/campaign_segment",
         params: { lead_ids: [create_lead(3).id], campaign_id: campaign.id, campaign_type: 'whatsapp_api', segment_name: 'Seleção' },
         headers: auth_headers(agent), as: :json

    expect(response).to have_http_status(:forbidden)
    expect(label_ids(campaign).size).to eq(1)
  end

  it 'campanha da API que já começou volta com o código de campanha inativa' do
    campaign.update!(status: :completed)

    post "#{base_url}/leads/campaign_segment",
         params: { lead_ids: [create_lead(4).id], campaign_id: campaign.id, campaign_type: 'whatsapp_api', segment_name: 'Seleção' },
         headers: auth_headers(admin), as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['code']).to eq('prospecting.campaign.campaign_not_active')
  end
end
