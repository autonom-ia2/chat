require 'rails_helper'

# Login único (#2338) com funções personalizadas e limite de caixas (os dois são EE). Ligar a Página segue a régua das
# caixas: com `meta_ads_manage`, criar caixa pede também `inbox_manage`, e trocar o token de uma caixa que já existe
# pede `integration_manage`. Sem a outra chave, 403 sem chamar a Meta. No limite de caixas, nada da Página fica gravado.
RSpec.describe 'Login único: ligar a Página com funções e limite (#2338)', type: :request do
  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true' do
      example.run
    end
  end

  let(:account) { create_account_and_user.first }
  let(:path) { "/api/v1/accounts/#{account.id}/crm/meta_ads_connection/pagina" }
  let(:page_id) { '104000000000001' }
  let(:json) { { 'Content-Type' => 'application/json' } }
  let(:koala_api) { instance_double(Koala::Facebook::API) }

  before do
    account.enable_features!('anuncios_login_unico')
    create_meta_ads_insights_connection(account)
    stub_request(:get, meta_graph_url(page_id)).with(query: hash_including(fields: 'access_token'))
                                               .to_return(status: 200, headers: json, body: { id: page_id, access_token: 'token-de-teste' }.to_json)
    allow(Koala::Facebook::API).to receive(:new).and_return(koala_api)
    allow(koala_api).to receive(:get_connections).and_return('name' => 'Loja Exemplo')
    allow(Facebook::Messenger::Subscriptions).to receive(:subscribe).and_return(true)
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

  it 'meta_ads_manage sem inbox_manage não cria a caixa da Página' do
    ligar(pessoa_com(%w[meta_ads_manage]))

    expect(response).to have_http_status(:forbidden)
    expect(Channel::FacebookPage.count).to eq(0)
    expect(a_request(:get, /graph\.facebook\.com/)).not_to have_been_made
  end

  it 'meta_ads_manage com inbox_manage cria a caixa' do
    expect { ligar(pessoa_com(%w[meta_ads_manage inbox_manage])) }.to change(account.inboxes, :count).by(1)

    expect(response).to have_http_status(:ok)
  end

  it 'meta_ads_manage sem integration_manage não troca o token de uma caixa que já existe' do
    channel = create(:channel_facebook_page, account: account, page_id: page_id)
    create(:inbox, account: account, channel: channel)

    ligar(pessoa_com(%w[meta_ads_manage inbox_manage]))

    expect(response).to have_http_status(:forbidden)
    expect(channel.reload.page_access_token).not_to eq('token-de-teste')
  end

  it 'no limite de caixas, a Página não fica gravada sem caixa' do
    account.update!(limits: { inboxes: account.inboxes.count })

    expect { ligar(account.administrators.first) }.not_to change(Channel::FacebookPage, :count)

    expect(response).to have_http_status(:payment_required)
  end
end
