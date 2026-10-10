require 'rails_helper'

# "Entrar com o Facebook" nos Anúncios da Meta (#1069): o código do Login do Facebook para Empresas vira token
# no servidor, é testado como a chave colada e grava a conexão no modo `facebook_login`. Nem o token, nem o
# código, nem o segredo do app voltam na resposta ou vão para o log.
RSpec.describe 'CRM meta_ads_connection facebook_login API', type: :request do
  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true' do
      example.run
    end
  end

  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:admin) { account_and_user.last }
  let(:agent) { create_crm_agent(account: account).first }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/meta_ads_connection" }
  let(:code) { 'AQBcodigodologindofacebook1234567890' }
  let(:token) { 'EAAGtokendologinfacebook0987654321SEGREDO' }
  let(:app_secret) { 'segredodoappdameta1234567890abcdef' }
  let(:ad_account) { '2196424464528988' }

  before { enable_test_encryption! }

  def configure_login
    { 'META_ADS_LOGIN_CONFIGURATION_ID' => '1575134603752871', 'WHATSAPP_APP_ID' => '544486745144318',
      'WHATSAPP_APP_SECRET' => app_secret }.each do |name, value|
      InstallationConfig.where(name: name).first_or_create(value: value).update!(value: value)
    end
    GlobalConfig.clear_cache('META_ADS_LOGIN_CONFIGURATION_ID', 'WHATSAPP_APP_ID', 'WHATSAPP_APP_SECRET')
  end

  def json(body, status: 200)
    { status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' } }
  end

  def stub_exchange(body, status: 200)
    stub_request(:get, meta_graph_url('oauth/access_token'))
      .with(query: { client_id: '544486745144318', client_secret: app_secret, code: code })
      .to_return(json(body, status: status))
  end

  def stub_graph(path, body, status: 200, query: hash_including({}))
    stub_request(:get, meta_graph_url(path)).with(query: query, headers: { 'Authorization' => "Bearer #{token}" })
                                            .to_return(json(body, status: status))
  end

  def stub_token_checks(permissions: [{ permission: 'ads_read', status: 'granted' }], accounts: [{ id: "act_#{ad_account}" }])
    stub_graph('me/permissions', { data: permissions })
    stub_graph('me/adaccounts', { data: accounts }, query: { limit: '1', fields: 'id' })
  end

  def expect_no_secret_in(text)
    [token, code, app_secret].each { |secret| expect(text).not_to include(secret) }
  end

  describe 'GET (o que a tela precisa para abrir o login)' do
    it 'sem a configuração, o login não aparece' do
      get base, headers: auth_headers(admin), as: :json

      expect(response.parsed_body['facebook_login']).to eq('available' => false)
    end

    it 'com a configuração, devolve o app e a configuração, nunca o segredo' do
      configure_login

      get base, headers: auth_headers(admin), as: :json

      expect(response.parsed_body['facebook_login']).to include('available' => true, 'app_id' => '544486745144318',
                                                                'configuration_id' => '1575134603752871')
      expect(response.body).not_to include(app_secret)
    end
  end

  describe 'POST facebook_login' do
    it 'troca o código, testa o token e grava no modo facebook_login, sem devolver segredo' do
      configure_login
      stub_exchange({ access_token: token, token_type: 'bearer' })
      stub_token_checks

      expect do
        post "#{base}/facebook_login", params: { code: code }, headers: auth_headers(admin), as: :json
      end.to have_enqueued_job(Crm::MetaAds::BackfillJob).with(account.id)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('configured' => true, 'mode' => 'facebook_login', 'status' => 'active')
      expect_no_secret_in(response.body)
      connection = Crm::MetaAdsConnection.find_by!(account_id: account.id)
      expect(connection.access_token).to eq(token)
      expect(connection.read_token).to eq(token)
      expect(connection.read_attribute_before_type_cast(:access_token)).not_to include(token)
    end

    it 'código recusado pela Meta vira login_failed, sem gravar e sem segredo no log' do
      configure_login
      stub_exchange({ error: { message: 'This authorization code has expired.', code: 100 } }, status: 400)
      logged = []
      allow(Rails.logger).to receive(:warn) { |line| logged << line }

      post "#{base}/facebook_login", params: { code: code }, headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('login_failed')
      expect(Crm::MetaAdsConnection.where(account_id: account.id)).to be_empty
      line = logged.find { |text| text.start_with?('[MetaAdsLogin]') }
      expect(line).to include('http=400', 'code=100', 'expired')
      expect_no_secret_in(logged.join("\n"))
    end

    it 'Meta fora do ar na troca vira meta_unavailable' do
      configure_login
      stub_exchange({ error: { message: 'Service unavailable', code: 2 } }, status: 503)

      post "#{base}/facebook_login", params: { code: code }, headers: auth_headers(admin), as: :json

      expect(response.parsed_body['error']).to eq('meta_unavailable')
    end

    it 'limite de uso da Meta na troca vira meta_unavailable, não login_failed' do
      configure_login
      stub_exchange({ error: { message: 'Application request limit reached', code: 4 } }, status: 400)

      post "#{base}/facebook_login", params: { code: code }, headers: auth_headers(admin), as: :json

      expect(response.parsed_body['error']).to eq('meta_unavailable')
    end

    it 'falha de rede na troca vira meta_unavailable, sem segredo no log' do
      configure_login
      stub_request(:get, meta_graph_url('oauth/access_token')).with(query: hash_including({})).to_timeout
      logged = []
      allow(Rails.logger).to receive(:warn) { |line| logged << line }

      post "#{base}/facebook_login", params: { code: code }, headers: auth_headers(admin), as: :json

      expect(response.parsed_body['error']).to eq('meta_unavailable')
      expect_no_secret_in(logged.join("\n"))
    end

    it 'trocar a chave colada pelo login limpa a conta escolhida antes: o token novo não lê a conta antiga sozinho' do
      configure_login
      old = create_meta_ads_connection(account)
      old.update!(ad_account_id: ad_account, ad_account_name: 'Antiga', pixel_id: '99', verified_at: Time.current)
      stub_exchange({ access_token: token })
      stub_token_checks

      post "#{base}/facebook_login", params: { code: code }, headers: auth_headers(admin), as: :json

      expect(response.parsed_body).to include('mode' => 'facebook_login', 'ad_account' => nil, 'pixel' => nil, 'verified_at' => nil)
      expect(old.reload).to have_attributes(ad_account_id: nil, pixel_id: nil, access_token: token)
      expect(old).not_to be_insights_readable
    end

    it 'entrar de novo pelo login mantém a conta escolhida, que a escolha seguinte confere' do
      configure_login
      Crm::MetaAdsConnection.create!(account: account, mode: 'facebook_login', access_token: 'EAAGtokenantigo1234567890', ad_account_id: ad_account)
      stub_exchange({ access_token: token })
      stub_token_checks

      post "#{base}/facebook_login", params: { code: code }, headers: auth_headers(admin), as: :json

      expect(Crm::MetaAdsConnection.find_by!(account_id: account.id)).to have_attributes(ad_account_id: ad_account, access_token: token)
    end

    it 'token sem ads_read vira missing_ads_read, sem gravar' do
      configure_login
      stub_exchange({ access_token: token })
      stub_token_checks(permissions: [{ permission: 'business_management', status: 'granted' }])

      post "#{base}/facebook_login", params: { code: code }, headers: auth_headers(admin), as: :json

      expect(response.parsed_body['error']).to eq('missing_ads_read')
      expect(Crm::MetaAdsConnection.where(account_id: account.id)).to be_empty
    end

    it 'nenhuma conta de anúncios marcada vira no_ad_account' do
      configure_login
      stub_exchange({ access_token: token })
      stub_token_checks(accounts: [])

      post "#{base}/facebook_login", params: { code: code }, headers: auth_headers(admin), as: :json

      expect(response.parsed_body['error']).to eq('no_ad_account')
    end

    it 'sem a configuração responde login_unavailable sem chamar a Meta' do
      exchange = stub_request(:get, meta_graph_url('oauth/access_token')).with(query: hash_including({}))

      post "#{base}/facebook_login", params: { code: code }, headers: auth_headers(admin), as: :json

      expect(response.parsed_body['error']).to eq('login_unavailable')
      expect(exchange).not_to have_been_requested
    end

    it 'sem código responde code_required' do
      configure_login

      post "#{base}/facebook_login", params: { code: ' ' }, headers: auth_headers(admin), as: :json

      expect(response.parsed_body['error']).to eq('code_required')
    end

    it 'quem não é administrador recebe 403' do
      configure_login

      post "#{base}/facebook_login", params: { code: code }, headers: auth_headers(agent), as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'passo 2 com o token do login' do
    def account_row
      { id: "act_#{ad_account}", account_id: ad_account, name: 'CA - Placement Seguros', account_status: 1, currency: 'BRL',
        timezone_name: 'America/Sao_Paulo', business: { id: '1013433763956648', name: 'Dono' } }
    end

    def connect_with_login
      enable_test_encryption!
      Crm::MetaAdsConnection.create!(account: account, mode: 'facebook_login', access_token: token)
    end

    it 'lista as contas que o login concedeu' do
      connect_with_login
      stub_graph('me/adaccounts', { data: [account_row] })
      stub_graph("act_#{ad_account}/insights", { data: [{ spend: '10' }] })

      get "#{base}/ad_accounts", params: { mode: 'facebook_login' }, headers: auth_headers(admin)

      expect(response.parsed_body['ad_accounts'].first).to include('id' => ad_account, 'ready' => true)
    end

    it 'não usa o token do login como se fosse a chave colada' do
      connect_with_login

      get "#{base}/pixels", params: { mode: 'token', ad_account_id: ad_account }, headers: auth_headers(admin)

      expect(response.parsed_body['error']).to eq('token_missing')
    end

    it 'não usa a chave colada como se fosse o login' do
      create_meta_ads_connection(account)

      get "#{base}/ad_accounts", params: { mode: 'facebook_login' }, headers: auth_headers(admin)

      expect(response.parsed_body['error']).to eq('token_missing')
    end

    it 'a escolha da conta mantém o token e o modo do login' do
      connect_with_login
      stub_graph("act_#{ad_account}", account_row)
      stub_graph("act_#{ad_account}/insights", { data: [{ spend: '10' }] })

      post "#{base}/selection", params: { mode: 'facebook_login', ad_account_id: ad_account }, headers: auth_headers(admin), as: :json

      expect(response.parsed_body).to include('mode' => 'facebook_login', 'status' => 'active')
      connection = Crm::MetaAdsConnection.find_by!(account_id: account.id)
      expect(connection.access_token).to eq(token)
      expect(connection).to be_readable
    end
  end
end
