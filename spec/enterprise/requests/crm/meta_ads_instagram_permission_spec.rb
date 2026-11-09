require 'rails_helper'

# Instagram pelo login único (#2406) com funções personalizadas e limite de caixas (os dois são EE). A mesma régua da
# Página (#2338): com `meta_ads_manage`, criar a caixa do Instagram pede também `inbox_manage`, e trocar o login de uma
# caixa que já existe pede `integration_manage`. No limite de caixas, nada do Instagram fica gravado.
RSpec.describe 'Login único: ligar o Instagram com funções e limite (#2406)', type: :request do
  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true' do
      example.run
    end
  end

  let(:account) { create_account_and_user.first }
  let(:path) { "/api/v1/accounts/#{account.id}/crm/meta_ads_connection/instagram" }
  let(:page_id) { '104000000000001' }
  let(:instagram_id) { '17841400000000001' }
  let(:json) { { 'Content-Type' => 'application/json' } }

  before do
    account.enable_features!('anuncios_login_unico', 'instagram_login_unico')
    create_meta_ads_insights_connection(account)
    page = { id: page_id, name: 'Loja Exemplo', instagram_business_account: { id: instagram_id, username: 'lojaexemplo' } }
    stub_request(:get, meta_graph_url('me/accounts')).with(query: hash_including({}))
                                                     .to_return(status: 200, headers: json, body: { data: [page] }.to_json)
    rows = %w[instagram_basic instagram_manage_messages pages_manage_metadata].map { |name| { permission: name, status: 'granted' } }
    stub_request(:get, meta_graph_url('me/permissions')).to_return(status: 200, headers: json, body: { data: rows }.to_json)
    stub_request(:get, meta_graph_url(page_id)).with(query: hash_including(fields: 'access_token'))
                                               .to_return(status: 200, headers: json, body: { id: page_id, access_token: 'token-de-teste' }.to_json)
  end

  def pessoa_com(permissions)
    user = create(:user, account: account, role: :agent)
    role = CustomRole.create!(account: account, name: "Cargo #{SecureRandom.hex(4)}", permissions: permissions)
    AccountUser.find_by(account: account, user: user).update!(custom_role: role)
    user
  end

  def ligar(user)
    post path, params: { page_id: page_id }, headers: user.create_new_auth_token, as: :json
  end

  it 'meta_ads_manage sem inbox_manage não cria a caixa do Instagram' do
    ligar(pessoa_com(%w[meta_ads_manage]))

    expect(response).to have_http_status(:forbidden)
    expect(Channel::Instagram.count).to eq(0)
  end

  it 'meta_ads_manage com inbox_manage cria a caixa' do
    expect { ligar(pessoa_com(%w[meta_ads_manage inbox_manage])) }.to change(account.inboxes, :count).by(1)

    expect(response).to have_http_status(:ok)
  end

  it 'meta_ads_manage com inbox_manage e sem integration_manage não troca o login de uma caixa que já existe' do
    channel = create(:channel_instagram, account: account, instagram_id: instagram_id)

    ligar(pessoa_com(%w[meta_ads_manage inbox_manage]))

    expect(response).to have_http_status(:forbidden)
    expect(channel.reload.login).to eq('instagram')
  end

  it 'meta_ads_manage com integration_manage troca o login' do
    channel = create(:channel_instagram, account: account, instagram_id: instagram_id)

    ligar(pessoa_com(%w[meta_ads_manage integration_manage]))

    expect(response).to have_http_status(:ok)
    expect(channel.reload.login).to eq('facebook')
  end

  it 'no limite de caixas, o Instagram não fica gravado sem caixa' do
    account.update!(limits: { inboxes: account.inboxes.count })

    expect { ligar(account.administrators.first) }.not_to change(Channel::Instagram, :count)

    expect(response).to have_http_status(:payment_required)
  end
end
