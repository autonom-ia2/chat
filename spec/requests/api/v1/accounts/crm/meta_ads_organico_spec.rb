require 'rails_helper'

# Seus posts (#2199): GET meta_ads_connection/organico?days=7|30|90. Atrás da flag `meta_ads_organico` (404 desligada);
# quem vê os Anúncios da Meta vê (administrador ou `meta_ads_view`); período inválido 422; Meta fora 503.
RSpec.describe 'CRM meta_ads_connection organico API', type: :request do
  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true' do
      example.run
    end
  end

  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:admin) { account_and_user.last }
  let(:path) { "/api/v1/accounts/#{account.id}/crm/meta_ads_connection/organico" }

  before { account.enable_features!('meta_ads_organico') }

  it 'devolve a Página e o Instagram no formato da tela' do
    get path, params: { days: 7 }, headers: auth_headers(admin), as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('days' => 7, 'page' => { 'status' => 'not_connected' },
                                            'instagram' => { 'status' => 'not_connected' })
  end

  it 'com a flag desligada, 404' do
    account.disable_features!('meta_ads_organico')

    get path, params: { days: 7 }, headers: auth_headers(admin), as: :json

    expect(response).to have_http_status(:not_found)
  end

  it 'período fora de 7, 30 e 90 dias, 422' do
    get path, params: { days: 15 }, headers: auth_headers(admin), as: :json

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'agente sem meta_ads_view, 403' do
    agent = create(:user, account: account, role: :agent)

    get path, params: { days: 7 }, headers: auth_headers(agent), as: :json

    expect(response).to have_http_status(:forbidden)
  end

  it 'Meta fora do ar, 503 com meta_unavailable' do
    allow(Crm::MetaAds::Organico::Tela).to receive(:new).and_raise(Crm::MetaAds::Organico::Indisponivel)

    get path, params: { days: 7 }, headers: auth_headers(admin), as: :json

    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body).to eq('error' => 'meta_unavailable')
  end
end
