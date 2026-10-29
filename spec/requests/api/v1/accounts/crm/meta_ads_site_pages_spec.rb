require 'rails_helper'

# Anúncios › Destino (#2338): a página do site é ligada ali mesmo. Listar pede meta_ads_view e não traz cliques,
# conversas nem valores (esses seguem atrás de campaign_view em Links e QR codes). Criar pede meta_ads_manage e sai
# sempre como link de site. Editar e apagar continuam em Links e QR codes.
RSpec.describe 'CRM meta_ads_connection site pages (#2338)', type: :request do
  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true', FRONTEND_URL: 'https://chat.example.com' do
      example.run
    end
  end

  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:admin) { account_and_user.last }
  let(:path) { "/api/v1/accounts/#{account.id}/crm/meta_ads_connection/site_pages" }
  let(:inbox) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false).inbox
  end
  let(:create_params) { { name: 'Site loja.com.br', inbox_id: inbox.id, allowed_origins: ['https://loja.com.br'] } }

  before { account.enable_features!('meta_ads_hub') }

  def user_with(permissions)
    user = create(:user, account: account, role: :agent)
    AccountUser.find_by!(account: account, user: user).update!(custom_role: create(:custom_role, account: account, permissions: permissions))
    user
  end

  def website_link(name)
    Ctwa::TrackedLink.create!(account: account, inbox: inbox, name: name, usage: 'website', allowed_origins: ['https://loja.com.br'])
  end

  it 'sem a flag responde 404' do
    account.disable_features!('meta_ads_hub')

    get path, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
  end

  it 'quem só tem meta_ads_manage liga a página, e ela sai como link de site mesmo pedindo outro uso' do
    user = user_with(%w[meta_ads_manage])

    expect do
      post path, params: create_params.merge(usage: 'direct', prefilled_text: 'Oi'), headers: user.create_new_auth_token, as: :json
    end.to change(Ctwa::TrackedLink, :count).by(1)

    expect(response).to have_http_status(:created)
    link = Ctwa::TrackedLink.last
    expect(link).to have_attributes(account_id: account.id, inbox_id: inbox.id, name: 'Site loja.com.br', usage: 'website',
                                    allowed_origins: ['https://loja.com.br'])
    expect(response.parsed_body['payload']).to include('id' => link.id, 'name' => 'Site loja.com.br', 'usage' => 'website',
                                                       'allowed_origins' => ['https://loja.com.br'],
                                                       'kit_url' => "https://chat.example.com/l/#{link.code}/kit")
  end

  it 'quem só tem meta_ads_view lista as páginas de site, sem cliques, conversas nem valores, e não cria' do
    website_link('Site loja.com.br')
    Ctwa::TrackedLink.create!(account: account, inbox: inbox, name: 'QR balcão', usage: 'direct')
    user = user_with(%w[meta_ads_view])

    get path, headers: user.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    page = response.parsed_body['payload'].sole
    expect(page).to include('name' => 'Site loja.com.br', 'usage' => 'website', 'inbox_id' => inbox.id)
    # Lista fechada: campo novo aqui passa pela sessão de Funções (sem contagem e sem R$).
    expect(page.keys).to match_array(%w[id name code usage inbox_id allowed_origins last_signal_at signals_blocked signal_url
                                        kit_url ad_url_params])

    post path, params: create_params, headers: user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
  end

  it 'sem chave de Anúncios não lista nem cria' do
    user = user_with(%w[campaign_manage])

    get path, headers: user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)

    expect do
      post path, params: create_params, headers: user.create_new_auth_token, as: :json
    end.not_to change(Ctwa::TrackedLink, :count)
    expect(response).to have_http_status(:forbidden)
  end

  it 'não liga página em caixa de outra conta' do
    other_inbox = create(:channel_whatsapp, account: create(:account), provider: 'whatsapp_cloud', validate_provider_config: false,
                                            sync_templates: false).inbox

    expect do
      post path, params: create_params.merge(inbox_id: other_inbox.id), headers: admin.create_new_auth_token, as: :json
    end.not_to change(Ctwa::TrackedLink, :count)
    expect(response).to have_http_status(:not_found)
  end

  it 'a conexão diz quantas páginas de site estão ligadas' do
    create_meta_ads_connection(account)
    website_link('Site loja.com.br')
    Ctwa::TrackedLink.create!(account: account, inbox: inbox, name: 'QR balcão', usage: 'direct')

    get "/api/v1/accounts/#{account.id}/crm/meta_ads_connection", headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body['site_pages_count']).to eq(1)
  end

  it 'diz qual página bateu o teto diário de avisos' do
    stub_const('Ctwa::TrackedLink::SIGNALS_DAILY_LIMIT', 2)
    full = website_link('Site cheio')
    website_link('Site livre')
    create_list(:ctwa_tracked_link_click, 2, account: account, tracked_link: full)

    get path, headers: admin.create_new_auth_token, as: :json

    blocked = response.parsed_body['payload'].to_h { |page| [page['name'], page['signals_blocked']] }
    expect(blocked).to eq('Site cheio' => true, 'Site livre' => false)
  end
end
