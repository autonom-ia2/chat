require 'rails_helper'

# Instagram pelo login único (#2406): o Instagram da Página liga com o mesmo login dos Anúncios. Sem as duas flags 404
# sem chamar a Meta; agente comum 403; a caixa nasce com o token da Página e o login do Facebook, ou a caixa do mesmo
# Instagram troca de login; sem as permissões do Instagram, nada muda.
RSpec.describe 'CRM meta_ads_connection Instagram do login único (#2406)', type: :request do
  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true' do
      example.run
    end
  end

  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:admin) { account_and_user.last }
  let(:agent) { create_crm_agent(account: account).first }
  let(:path) { "/api/v1/accounts/#{account.id}/crm/meta_ads_connection/instagram" }
  let(:json) { { 'Content-Type' => 'application/json' } }
  let(:page_id) { '104000000000001' }
  let(:instagram_id) { '17841400000000001' }
  let(:page_token) { 'token-da-pagina-de-teste' }
  let(:granted) { %w[ads_read instagram_basic instagram_manage_messages pages_manage_metadata] }

  before do
    account.enable_features!('anuncios_login_unico', 'instagram_login_unico')
    create_meta_ads_insights_connection(account)
  end

  def stub_meta(instagram: { id: instagram_id, username: 'lojaexemplo' }, permissions: granted)
    page = { id: page_id, name: 'Loja Exemplo', instagram_business_account: instagram }.compact
    stub_request(:get, meta_graph_url('me/accounts')).with(query: hash_including({}))
                                                     .to_return(status: 200, headers: json, body: { data: [page] }.to_json)
    rows = permissions.map { |name| { permission: name, status: 'granted' } }
    stub_request(:get, meta_graph_url('me/permissions')).to_return(status: 200, headers: json, body: { data: rows }.to_json)
    stub_request(:get, meta_graph_url(page_id)).with(query: hash_including(fields: 'access_token'))
                                               .to_return(status: 200, headers: json, body: { id: page_id, access_token: page_token }.to_json)
  end

  def link(user = admin, id = page_id)
    post path, params: { page_id: id }, headers: user.create_new_auth_token, as: :json
  end

  it 'sem a flag do Instagram responde 404 e não chama a Meta' do
    account.disable_features!('instagram_login_unico')

    link

    expect(response).to have_http_status(:not_found)
    expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
  end

  it 'agente comum não liga' do
    link(agent)

    expect(response).to have_http_status(:forbidden)
    expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
  end

  it 'cria a caixa do Instagram no login do Facebook, com o token da Página, sem devolver o token' do
    stub_meta

    expect { link }.to change(Channel::Instagram, :count).by(1).and have_enqueued_job(Instagram::PageSubscribeJob)

    channel = Channel::Instagram.last
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq('inbox_id' => channel.inbox.id, 'name' => 'lojaexemplo')
    expect(response.body).not_to include(page_token)
    expect(channel).to have_attributes(account_id: account.id, instagram_id: instagram_id, login: 'facebook', page_id: page_id,
                                       provider_name: 'lojaexemplo')
    expect(channel.access_token).to eq(page_token)
  end

  it 'a caixa do mesmo Instagram, do login do Instagram, troca de login e fica a mesma' do
    stub_meta
    existing = create(:channel_instagram, account: account, instagram_id: instagram_id)

    expect { link }.not_to change(Channel::Instagram, :count)

    expect(response).to have_http_status(:ok)
    expect(existing.reload).to have_attributes(login: 'facebook', page_id: page_id)
    expect(existing.access_token).to eq(page_token)
    expect(response.parsed_body['inbox_id']).to eq(existing.inbox.id)
  end

  it 'trocar o login de uma caixa pede integration_manage' do
    stub_meta
    create(:channel_instagram, account: account, instagram_id: instagram_id)
    account.account_users.find_by(user: admin).update!(role: :agent)

    link

    expect(response).to have_http_status(:forbidden)
  end

  it 'login sem as permissões do Instagram: 422 missing_permissions e nada é criado' do
    stub_meta(permissions: %w[ads_read pages_manage_metadata])

    expect { link }.not_to change(Channel::Instagram, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('missing_permissions')
  end

  it 'Página sem Instagram: 422 no_instagram' do
    stub_meta(instagram: nil)

    expect { link }.not_to change(Channel::Instagram, :count)

    expect(response.parsed_body['error']).to eq('no_instagram')
  end

  it 'page_id que não é número: 422 page_id_required, sem chamar a Meta' do
    link(admin, '1/me')

    expect(response.parsed_body['error']).to eq('page_id_required')
    expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
  end
end
