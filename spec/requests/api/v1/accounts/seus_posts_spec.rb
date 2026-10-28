require 'rails_helper'

# Seus posts (#2302, F1 #2304): GET seus_posts?perfil=&days=. Atrás da flag `seus_posts` (404 desligada);
# administrador ou `posts_view`; período inválido 422; perfil de outra conta 404.
RSpec.describe 'Seus posts API', type: :request do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:admin) { account_and_user.last }
  let(:path) { "/api/v1/accounts/#{account.id}/seus_posts" }

  before { account.enable_features!('seus_posts') }

  it 'conta sem Instagram nem Página: sem perfis' do
    get path, params: { days: 30 }, headers: auth_headers(admin), as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('days' => 30, 'perfis' => [], 'perfil' => nil)
  end

  it 'com a flag desligada, 404' do
    account.disable_features!('seus_posts')

    get path, params: { days: 30 }, headers: auth_headers(admin), as: :json

    expect(response).to have_http_status(:not_found)
  end

  it 'período fora de 7, 30 e 90 dias, 422' do
    get path, params: { days: 15 }, headers: auth_headers(admin), as: :json

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'período em lista ou objeto no endereço, 422 (não 500)' do
    ["#{path}?days[]=30", "#{path}?days[x]=30"].each do |endereco|
      get endereco, headers: auth_headers(admin)

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  it 'agente sem posts_view, 403' do
    agent = create(:user, account: account, role: :agent)

    get path, params: { days: 30 }, headers: auth_headers(agent), as: :json

    expect(response).to have_http_status(:forbidden)
  end

  it 'perfil que não é da conta, 404' do
    outra = create(:account)
    canal = create(:channel_instagram, account: outra)

    get path, params: { days: 30, perfil: "instagram-#{canal.id}" }, headers: auth_headers(admin), as: :json

    expect(response).to have_http_status(:not_found)
  end
end
