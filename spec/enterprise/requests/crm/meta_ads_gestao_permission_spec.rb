require 'rails_helper'

# Gestão mínima do anúncio (#2161) com funções personalizadas: `meta_ads_view` vê a situação e o post, mas nunca
# pode mudar (can_change false, POST 403 sem chamar a Meta); `meta_ads_manage` muda. Fica em spec/enterprise: a metade
# de função personalizada do permission_granted? é EE.
RSpec.describe 'Anúncios da Meta: gestão do anúncio com funções (#2161)', type: :request do
  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true' do
      example.run
    end
  end

  let(:account) { create_account_and_user.first }
  let(:path) { "/api/v1/accounts/#{account.id}/crm/meta_ads_connection" }
  let(:ad_id) { '120254710382770416' }
  let(:json) { { 'Content-Type' => 'application/json' } }

  before do
    account.enable_features!('meta_ads_gestao')
    create_meta_ads_insights_connection(account)
    stub_request(:get, meta_graph_url('me/permissions'))
      .to_return(status: 200, body: { data: [{ permission: 'ads_management', status: 'granted' }] }.to_json, headers: json)
    stub_request(:get, meta_graph_url(ad_id)).with(query: hash_including({}))
                                             .to_return(status: 200, headers: json,
                                                        body: { id: ad_id, account_id: '2196424464528988', status: 'ACTIVE',
                                                                effective_status: 'ACTIVE', creative: { id: '9' } }.to_json)
  end

  def pessoa_com(permissions)
    user = create(:user, account: account, role: :agent)
    role = CustomRole.create!(account: account, name: "Cargo #{SecureRandom.hex(4)}", permissions: permissions)
    AccountUser.find_by(account: account, user: user).update!(custom_role: role)
    user
  end

  it 'meta_ads_view vê a situação sem poder mudar, e o POST é recusado sem chamar a Meta' do
    viewer = pessoa_com(%w[meta_ads_view])

    get "#{path}/ads/#{ad_id}/management", headers: viewer.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['management']).to include('status' => 'ACTIVE', 'can_change' => false)

    post "#{path}/ads/#{ad_id}/status", params: { status: 'PAUSED' }, headers: viewer.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(a_request(:post, /graph\.facebook\.com/)).not_to have_been_made
  end

  it 'meta_ads_manage pausa' do
    manager = pessoa_com(%w[meta_ads_manage])
    stub_request(:post, meta_graph_url(ad_id)).to_return(status: 200, body: { success: true }.to_json, headers: json)

    post "#{path}/ads/#{ad_id}/status", params: { status: 'PAUSED' }, headers: manager.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq('status' => 'PAUSED')
  end
end
