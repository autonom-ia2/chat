require 'rails_helper'

# Login único (#2338): a Página vem do mesmo login dos Anúncios. Sem a flag 404 sem chamar a Meta; agente comum 403;
# a lista traz o Instagram ligado e o que a pessoa recusou; ligar cria a caixa da Página ou troca o token da que existe,
# sem o token sair na resposta.
RSpec.describe 'CRM meta_ads_connection página do login único (#2338)', type: :request do
  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true' do
      example.run
    end
  end

  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:admin) { account_and_user.last }
  let(:agent) { create_crm_agent(account: account).first }
  let(:path) { "/api/v1/accounts/#{account.id}/crm/meta_ads_connection" }
  let(:json) { { 'Content-Type' => 'application/json' } }
  let(:page_id) { '104000000000001' }
  let(:page_token) { 'token-da-pagina-de-teste' }
  let(:koala_api) { instance_double(Koala::Facebook::API) }

  before do
    account.enable_features!('anuncios_login_unico')
    create_meta_ads_insights_connection(account)
    allow(Koala::Facebook::API).to receive(:new).and_return(koala_api)
    allow(koala_api).to receive(:get_connections).with('me', '', { fields: 'name,instagram_business_account' })
                                                 .and_return('name' => 'Loja Exemplo')
    allow(Facebook::Messenger::Subscriptions).to receive(:subscribe).and_return(true)
  end

  def stub_pages(declined: [])
    instagram = { id: '1784', username: 'lojaexemplo', followers_count: 4820 }
    pages = [
      { id: page_id, name: 'Loja Exemplo', category: 'Loja de roupas', followers_count: 12_940, instagram_business_account: instagram },
      { id: '104000000000002', name: 'Blog', category: 'Blog pessoal' }
    ]
    stub_request(:get, meta_graph_url('me/accounts')).with(query: hash_including({}))
                                                     .to_return(status: 200, headers: json, body: { data: pages }.to_json)
    permissions = [{ permission: 'ads_read', status: 'granted' }] + declined.map { |name| { permission: name, status: 'declined' } }
    stub_request(:get, meta_graph_url('me/permissions')).to_return(status: 200, headers: json, body: { data: permissions }.to_json)
  end

  def stub_page_token(token: page_token)
    body = token ? { id: page_id, access_token: token } : { error: { code: 10, message: 'no permission' } }
    stub_request(:get, meta_graph_url(page_id)).with(query: hash_including(fields: 'access_token'))
                                               .to_return(status: token ? 200 : 400, headers: json, body: body.to_json)
  end

  it 'sem a flag responde 404 e não chama a Meta' do
    account.disable_features!('anuncios_login_unico')

    get "#{path}/paginas", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
    expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
  end

  it 'agente comum não lista nem liga' do
    get "#{path}/paginas", headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)

    post "#{path}/pagina", params: { page_id: page_id }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
  end

  it 'lista as Páginas com o Instagram ligado, se já têm caixa e o que a pessoa recusou' do
    stub_pages(declined: ['read_insights'])
    create(:channel_facebook_page, account: account, page_id: '104000000000002')

    get "#{path}/paginas", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['pages']).to eq(
      [
        { 'id' => page_id, 'name' => 'Loja Exemplo', 'category' => 'Loja de roupas', 'followers' => 12_940,
          'instagram' => { 'username' => 'lojaexemplo', 'followers' => 4820 }, 'linked' => false },
        { 'id' => '104000000000002', 'name' => 'Blog', 'category' => 'Blog pessoal', 'followers' => nil,
          'instagram' => nil, 'linked' => true }
      ]
    )
    expect(response.parsed_body['granted_permissions']).to eq(['ads_read'])
    expect(response.parsed_body['declined_permissions']).to eq(['read_insights'])
  end

  it 'no modo parceiro não lista Páginas: o token é o da plataforma' do
    Crm::MetaAdsConnection.find_by(account_id: account.id).update!(mode: 'partner')

    get "#{path}/paginas", headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body).to eq('pages' => [], 'granted_permissions' => [], 'declined_permissions' => [])
    expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
  end

  it 'liga uma Página sem caixa: cria a caixa com o nome da Página e o token dela, sem devolver o token' do
    stub_page_token

    expect do
      post "#{path}/pagina", params: { page_id: page_id }, headers: admin.create_new_auth_token, as: :json
    end.to change(account.inboxes, :count).by(1)

    expect(response).to have_http_status(:ok)
    inbox = account.inboxes.last
    expect(response.parsed_body).to eq('inbox_id' => inbox.id, 'name' => 'Loja Exemplo')
    expect(inbox.channel).to have_attributes(page_id: page_id, page_access_token: page_token)
    expect(response.body).not_to include(page_token)
  end

  it 'Página que já tem caixa: troca o token dela e não cria outra' do
    stub_page_token
    channel = create(:channel_facebook_page, account: account, page_id: page_id)
    create(:inbox, account: account, channel: channel)

    expect do
      post "#{path}/pagina", params: { page_id: page_id }, headers: admin.create_new_auth_token, as: :json
    end.not_to change(account.inboxes, :count)

    expect(response).to have_http_status(:ok)
    expect(channel.reload.page_access_token).to eq(page_token)
  end

  it 'a Meta não dá o token da Página: 422 page_not_granted e nada é criado' do
    stub_page_token(token: nil)

    expect do
      post "#{path}/pagina", params: { page_id: page_id }, headers: admin.create_new_auth_token, as: :json
    end.not_to change(Channel::FacebookPage, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('page_not_granted')
  end

  it 'sem page_id: 422 page_id_required' do
    post "#{path}/pagina", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('page_id_required')
  end
end
