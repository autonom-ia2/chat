require 'rails_helper'

# Credencial de leitura de anúncios da Meta (#1034). Só administrador; o token nunca volta.
RSpec.describe 'CRM meta_ads_connection API', type: :request do
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
  let(:token) { 'EAAGnovotoken9876543210zyxwvutSEGREDO' }

  before { enable_test_encryption! }

  def stub_permissions(body, status: 200)
    stub_request(:get, meta_graph_url('me/permissions'))
      .with(headers: { 'Authorization' => "Bearer #{token}" })
      .to_return(status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  def stub_ad_accounts(body, status: 200)
    stub_request(:get, meta_graph_url('me/adaccounts'))
      .with(query: { limit: '1', fields: 'id' }, headers: { 'Authorization' => "Bearer #{token}" })
      .to_return(status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  def expect_no_token_in(text)
    expect(text).not_to include(token)
    expect(text).not_to include(token.first(8))
    expect(text).not_to include(token.last(8))
  end

  describe 'GET' do
    it 'devolve não configurado quando a conta não tem credencial' do
      get path, headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('configured' => false, 'status' => nil, 'mode' => nil, 'last_checked_at' => nil, 'last_error' => nil)
      expect(response.parsed_body['partner']).to include('available' => false)
      expect(response.parsed_body['sales_signal']).to eq('enabled' => false)
    end

    it 'devolve o estado sem o token nem parte dele' do
      create_meta_ads_connection(account, token: token).update!(last_checked_at: Time.current, last_error: nil)

      get path, headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.keys).to contain_exactly('configured', 'status', 'mode', 'last_checked_at', 'last_error', 'verified_at',
                                                           'destinations', 'ad_account', 'pixel', 'partner', 'whatsapp_portfolio',
                                                           'client_portfolio_id', 'sales_signal')
      expect(response.parsed_body).to include('mode' => 'token', 'destinations' => { 'whatsapp' => false, 'site' => false })
      expect(response.parsed_body).to include('configured' => true, 'status' => 'active')
      expect_no_token_in(response.body)
    end

    it 'recusa agente com 403' do
      get path, headers: auth_headers(agent), as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'PUT' do
    it 'testa o token, grava cifrado, devolve o estado e enfileira a resolução retroativa' do
      permissions = stub_permissions({ data: [{ permission: 'ads_read', status: 'granted' }, { permission: 'public_profile', status: 'granted' }] })
      stub_ad_accounts({ data: [{ id: 'act_123' }] })

      expect do
        put path, params: { access_token: token }, headers: auth_headers(admin), as: :json
      end.to have_enqueued_job(Crm::MetaAds::BackfillJob).with(account.id)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('configured' => true, 'status' => 'active', 'last_error' => nil)
      expect(response.parsed_body['last_checked_at']).to be_present
      expect_no_token_in(response.body)
      expect(permissions).to have_been_requested.once
      expect(Crm::MetaAdsConnection.find_by(account_id: account.id).access_token).to eq(token)
    end

    it 'aceita o token dentro da chave meta_ads_connection e troca o token de uma credencial invalid' do
      create_meta_ads_connection(account, status: 'invalid').update!(last_error: 'antigo')
      stub_permissions({ data: [{ permission: 'ads_read', status: 'granted' }] })
      stub_ad_accounts({ data: [{ id: 'act_123' }] })

      put path, params: { meta_ads_connection: { access_token: token } }, headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:ok)
      connection = Crm::MetaAdsConnection.find_by(account_id: account.id)
      expect([connection.access_token, connection.status, connection.last_error]).to eq([token, 'active', nil])
    end

    it 'devolve 422 missing_ads_read quando o token não tem ads_read concedido, sem gravar' do
      stub_permissions({ data: [{ permission: 'ads_read', status: 'declined' }, { permission: 'pages_show_list', status: 'granted' }] })

      put path, params: { access_token: token }, headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('missing_ads_read')
      expect(Crm::MetaAdsConnection.count).to eq(0)
      expect_no_token_in(response.body)
    end

    it 'devolve 422 invalid_token quando a Meta recusa o token, sem gravar nem ecoar o erro dela' do
      stub_permissions(meta_graph_error(190, "Invalid OAuth access token #{token}"), status: 400)

      expect do
        put path, params: { access_token: token }, headers: auth_headers(admin), as: :json
      end.not_to have_enqueued_job(Crm::MetaAds::BackfillJob)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('invalid_token')
      expect(Crm::MetaAdsConnection.count).to eq(0)
      expect_no_token_in(response.body)
    end

    it 'devolve 422 no_ad_account quando o token tem ads_read mas nenhuma conta de anúncios atribuída, sem gravar' do
      stub_permissions({ data: [{ permission: 'ads_read', status: 'granted' }] })
      stub_ad_accounts({ data: [] })

      expect do
        put path, params: { access_token: token }, headers: auth_headers(admin), as: :json
      end.not_to have_enqueued_job(Crm::MetaAds::BackfillJob)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('no_ad_account')
      expect(Crm::MetaAdsConnection.count).to eq(0)
    end

    it 'devolve 422 meta_unavailable (e não invalid_token) quando a Meta está fora ou limitando, sem gravar' do
      [[meta_graph_error(4, 'Application request limit reached'), 400], [{}, 503]].each do |body, status|
        WebMock.reset!
        stub_permissions(body, status: status)

        put path, params: { access_token: token }, headers: auth_headers(admin), as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('meta_unavailable')
      end
      expect(Crm::MetaAdsConnection.count).to eq(0)
    end

    it 'devolve 422 meta_unavailable quando a falha passageira vem na consulta das contas de anúncios' do
      stub_permissions({ data: [{ permission: 'ads_read', status: 'granted' }] })
      stub_ad_accounts({}, status: 503)

      put path, params: { access_token: token }, headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('meta_unavailable')
      expect(Crm::MetaAdsConnection.count).to eq(0)
    end

    it 'devolve 422 access_token_too_long sem chamar a Meta' do
      put path, params: { access_token: 'E' * 2049 }, headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('access_token_too_long')
      expect(a_request(:get, meta_graph_url('me/permissions'))).not_to have_been_made
    end

    it 'devolve 422 access_token_required sem token e não chama a Meta' do
      put path, params: { access_token: '  ' }, headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('access_token_required')
      expect(a_request(:get, meta_graph_url('me/permissions'))).not_to have_been_made
    end

    it 'devolve 422 encryption_not_configured sem o cofre e não chama a Meta' do
      allow(Chatwoot).to receive(:encryption_configured?).and_return(false)

      put path, params: { access_token: token }, headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('encryption_not_configured')
      expect(a_request(:get, meta_graph_url('me/permissions'))).not_to have_been_made
    end

    it 'recusa agente com 403 sem chamar a Meta nem gravar' do
      put path, params: { access_token: token }, headers: auth_headers(agent), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(Crm::MetaAdsConnection.count).to eq(0)
      expect(a_request(:get, meta_graph_url('me/permissions'))).not_to have_been_made
    end
  end

  it 'o access_token sai filtrado dos logs de parâmetros' do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)

    expect(filter.filter('access_token' => token, 'meta_ads_connection' => { 'access_token' => token }))
      .to eq('access_token' => '[FILTERED]', 'meta_ads_connection' => { 'access_token' => '[FILTERED]' })
  end

  describe 'DELETE' do
    it 'apaga a credencial e mantém os nomes já resolvidos' do
      create_meta_ads_connection(account)
      Crm::MetaAdObject.create!(account: account, meta_object_id: '120254710067060416', object_type: 'campaign',
                                name: 'Viagem EUA', fetched_at: Time.current)

      delete path, headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['configured']).to be(false)
      expect(Crm::MetaAdsConnection.where(account_id: account.id)).to be_empty
      expect(Crm::MetaAdObject.where(account_id: account.id).count).to eq(1)
    end

    it 'recusa agente com 403 e não apaga' do
      create_meta_ads_connection(account)

      delete path, headers: auth_headers(agent), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(Crm::MetaAdsConnection.where(account_id: account.id).count).to eq(1)
    end
  end

  describe 'GET panel (#1088)' do
    let(:connection) { create_meta_ads_insights_connection(account) }

    after do
      Crm::MetaAds::Insights::Refresh.release(connection.id, 'today')
      Crm::MetaAds::Insights::Backfill.release(connection.id)
      Redis::Alfred.delete("#{Crm::MetaAds::LinksBackfillJob::RUNNING_KEY}:#{connection.id}")
    end

    # O consultor de verdade (sem stub): grava o run do dia e devolve o Advice dele.
    it 'devolve o painel do período com o consultor, e pede a leitura de hoje' do
      connection.update!(insights_backfilled_at: 1.day.ago, links_backfilled_at: 1.day.ago)

      expect do
        get "#{path}/panel", params: { days: 7 }, headers: auth_headers(admin)
      end.to have_enqueued_job(Crm::MetaAds::InsightsSyncJob).with(connection.id, 'today')

      panel = response.parsed_body['panel']
      expect(panel).to include('days' => 7, 'currency' => 'BRL', 'refreshing' => true, 'meta_comparison' => nil, 'response_time' => nil)
      expect(panel).not_to have_key('action')
      expect(panel['totals']).to include('spend' => 0.0, 'conversations' => 0, 'sales' => 0)
      expect(panel['confidence']).to include('window_days' => 7, 'conversations' => 0)
      run = Crm::MetaAdvisorRun.sole
      expect(panel['advice']).to include('run_id' => run.id, 'local_date' => run.local_date.iso8601, 'rules_version' => 'f5.2')
      expect(panel['advice']['actions'].pluck('kind')).to eq(%w[no_data])
    end

    it 'com conversa de anúncio no período: a Meta × nós até ontem, o tempo de resposta e o consultor' do
      travel_to(Time.zone.parse('2026-10-07T15:00:00-03:00')) do
        connection.update!(destinations: { 'whatsapp' => true }, insights_backfilled_at: 1.day.ago, links_backfilled_at: 1.day.ago)
        Crm::MetaAdInsightDaily.create!(account: account, ad_account_id: connection.ad_account_id, ad_id: '1', date: Date.new(2026, 10, 6),
                                        currency: 'BRL', spend: 30, conversations_started: 5, attribution_window: '7d_click',
                                        fetched_at: Time.current)
        conversation = create(:conversation, account: account)
        Crm::MetaAdLink.create!(account: account, conversation: conversation, touch_key: 'k1', origin: 'whatsapp',
                                certainty: 'ad', ad_id: '1', ad_account_id: connection.ad_account_id, touched_at: 1.day.ago)
        create(:message, account: account, inbox: conversation.inbox, conversation: conversation, message_type: :incoming, created_at: 1.day.ago)
        create(:message, account: account, inbox: conversation.inbox, conversation: conversation, message_type: :outgoing,
                         created_at: 1.day.ago + 6.minutes)

        allow(Crm::MetaAds::Panel::ResponseTime).to receive(:new).and_call_original

        get "#{path}/panel", params: { days: 30 }, headers: auth_headers(admin)

        # Com 30 dias o tempo de resposta sai dos fatos do consultor: uma consulta só, a dos fatos.
        expect(Crm::MetaAds::Panel::ResponseTime).to have_received(:new).once
        panel = response.parsed_body['panel']
        expect(panel['meta_comparison']).to eq(
          'days' => 30, 'until' => '2026-10-06', 'explanation' => nil,
          'rows' => [{ 'destination' => 'whatsapp', 'meta' => 5, 'ours' => 1, 'difference' => -4, 'explanation' => 'meta_higher' }]
        )
        expect(panel['response_time']).to eq('days' => 30, 'median_seconds' => 360.0, 'answered' => 1, 'unanswered' => 0, 'slow' => 1,
                                             'target_seconds' => 300)
        expect(panel['advice']).to include('run_id' => Crm::MetaAdvisorRun.sole.id, 'local_date' => '2026-10-07')
        expect(panel['advice']['actions'].first).to include('kind' => 'wait', 'ad_id' => '1')
      end
    end

    # D5.11: a métrica de aceite conta só o que o painel mostrou; o Guia lê o painel pelo token de API.
    it 'só o painel (sessão) marca as ações como mostradas; o pedido pelo token de API não' do
      travel_to(Time.zone.parse('2026-10-07T15:00:00-03:00')) do
        connection.update!(insights_backfilled_at: 1.day.ago, links_backfilled_at: 1.day.ago)
        Crm::MetaAdLink.create!(account: account, conversation: create(:conversation, account: account), touch_key: 'k1', origin: 'whatsapp',
                                certainty: 'campaign', ad_account_id: connection.ad_account_id, touched_at: 1.day.ago)
        allow(Crm::MetaAds::Advisor::Rules).to receive(:evaluate).and_wrap_original do |original, *args, **options|
          original.call(*args, **options).map { |result| result[:key] == 'tracking' ? result.merge(status: 'fail') : result }
        end

        get "#{path}/panel", params: { days: 7 }, headers: auth_headers(admin)
        action = Crm::MetaAdvisorAction.find_by!(account_id: account.id, kind: 'fix_tracking')
        expect(action.shown_at).to be_nil

        get "#{path}/panel", params: { days: 7 }, headers: admin.create_new_auth_token
        expect(response).to have_http_status(:ok)
        expect(action.reload.shown_at).to eq(Time.current)
      end
    end

    it 'sem conta de anúncios devolve vazio' do
      get "#{path}/panel", headers: auth_headers(admin)

      expect(response.parsed_body).to eq('panel' => nil)
    end

    it 'agente recebe 403' do
      get "#{path}/panel", headers: auth_headers(agent)

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'GET panel_list (#1110, F5)' do
    let(:pipeline) { create_crm_pipeline(account: account, user: admin).first }
    let(:quote_stage) do
      account.crm_pipeline_stages.create!(pipeline: pipeline, name: 'Proposta', position: 1, metadata: { 'funnel_stage_type' => 'opportunity' })
    end

    it 'devolve a lista da etapa, da mesma coorte do painel' do
      travel_to(Time.zone.parse('2026-10-07T15:00:00-03:00')) do
        connection = create_meta_ads_insights_connection(account)
        conversation = create(:conversation, account: account)
        Crm::MetaAdLink.create!(account: account, conversation: conversation, touch_key: 'k1', origin: 'whatsapp', certainty: 'ad',
                                ad_id: '1', ad_account_id: connection.ad_account_id, touched_at: 2.days.ago)
        card = Crm::Card.create!(account: account, pipeline: pipeline, stage: quote_stage, title: 'Cotação', currency: 'BRL',
                                 primary_conversation: conversation, value_cents: 150_000, last_message_at: 5.days.ago)

        get "#{path}/panel_list", params: { step: 'quotes', days: 7 }, headers: auth_headers(admin)

        expect(response).to have_http_status(:ok)
        list = response.parsed_body['list']
        expect(list).to include('step' => 'quotes', 'days' => 7, 'total' => 1)
        expect(list['items'].sole).to include('conversation_id' => conversation.id, 'card_id' => card.id, 'title' => 'Cotação',
                                              'stage_name' => 'Proposta', 'status' => 'open', 'value' => 1500.0, 'stalled' => true)
      end
    end

    it 'etapa fora da lista dá 422 invalid_step' do
      create_meta_ads_insights_connection(account)

      get "#{path}/panel_list", params: { step: 'spend', days: 7 }, headers: auth_headers(admin)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'invalid_step')
    end

    it 'sem conexão devolve vazio' do
      get "#{path}/panel_list", params: { step: 'quotes' }, headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('list' => nil)
    end

    it 'agente recebe 403' do
      get "#{path}/panel_list", params: { step: 'quotes' }, headers: auth_headers(agent)

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'GET panel_ad (#1088, F3b)' do
    let(:ad_id) { '120254710362980416' }

    it 'devolve o anúncio por dentro, só do banco' do
      travel_to(Time.zone.parse('2026-10-06T15:00:00-03:00')) do
        connection = create_meta_ads_insights_connection(account)
        Crm::MetaAdInsightDaily.create!(account: account, ad_account_id: connection.ad_account_id, ad_id: ad_id, date: Date.new(2026, 10, 6),
                                        currency: 'BRL', spend: 42.5, attribution_window: '7d_click', fetched_at: Time.current)

        expect do
          get "#{path}/panel_ad", params: { ad_id: ad_id, days: 7 }, headers: auth_headers(admin)
        end.not_to have_enqueued_job(Crm::MetaAds::InsightsSyncJob)

        ad = response.parsed_body['ad']
        expect(ad).to include('ad_id' => ad_id, 'days' => 7, 'spend' => 42.5, 'verdict' => 'early', 'quotes_list' => [])
        expect(ad['reason']).to include('kind' => 'early', 'missing_conversations' => 20)
        expect(ad['daily'].last).to eq('date' => '2026-10-06', 'spend' => 42.5, 'conversations' => 0)
      end
    end

    it 'anúncio sem dado no período devolve vazio' do
      create_meta_ads_insights_connection(account)

      get "#{path}/panel_ad", params: { ad_id: ad_id }, headers: auth_headers(admin)

      expect(response.parsed_body).to eq('ad' => nil)
    end

    it 'sem conexão devolve vazio' do
      get "#{path}/panel_ad", params: { ad_id: ad_id }, headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('ad' => nil)
    end

    it 'agente recebe 403' do
      get "#{path}/panel_ad", params: { ad_id: ad_id }, headers: auth_headers(agent)

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'POST insights (#1073)' do
    let(:connection) { create_meta_ads_insights_connection(account) }

    after { Crm::MetaAds::Insights::Refresh.release(connection.id, 'today') }

    it 'devolve o último dia lido e pede a leitura de hoje quando está velha' do
      [['1', 30, 2], ['2', 12.5, 1]].each do |ad_id, spend, conversations|
        Crm::MetaAdInsightDaily.create!(account: account, ad_account_id: connection.ad_account_id, ad_id: ad_id, date: Date.new(2026, 10, 5),
                                        currency: 'BRL', spend: spend, conversations_started: conversations, attribution_window: '7d_click',
                                        fetched_at: Time.current)
      end

      expect do
        post "#{path}/insights", headers: auth_headers(admin), as: :json
      end.to have_enqueued_job(Crm::MetaAds::InsightsSyncJob).with(connection.id, 'today')

      expect(response.parsed_body['insights']).to include('date' => '2026-10-05', 'spend' => '42.5', 'currency' => 'BRL',
                                                          'conversations' => 3, 'refreshing' => true)
    end

    it 'várias aberturas ao mesmo tempo geram uma leitura só' do
      connection

      expect do
        2.times { post "#{path}/insights", headers: auth_headers(admin), as: :json }
      end.to have_enqueued_job(Crm::MetaAds::InsightsSyncJob).exactly(:once)
      expect(response.parsed_body['insights']).to include('refreshing' => true, 'date' => nil)
    end

    it 'lido há menos de 2 minutos não chama a Meta de novo' do
      connection.update!(insights_synced_at: 1.minute.ago, insights_backfilled_at: 1.day.ago)

      expect do
        post "#{path}/insights", headers: auth_headers(admin), as: :json
      end.not_to have_enqueued_job(Crm::MetaAds::InsightsSyncJob)
      expect(response.parsed_body['insights']['refreshing']).to be(false)
    end

    it 'sem a carga de 90 dias, abrir a tela começa a carga na hora e avisa que está buscando' do
      connection.update!(insights_synced_at: 1.minute.ago)

      expect do
        post "#{path}/insights", headers: auth_headers(admin), as: :json
      end.to have_enqueued_job(Crm::MetaAds::InsightsBackfillJob).with(connection.id)
                                                                 .and have_enqueued_job(Crm::MetaAds::LinksBackfillJob).with(connection.id)
      expect(response.parsed_body['insights']).to include('backfilling' => true, 'ad_conversations_today' => 0)
      expect(response.parsed_body['insights']['confidence']).to include('conversations' => 0, 'window_days' => 30)
    ensure
      Crm::MetaAds::Insights::Backfill.release(connection.id)
      Redis::Alfred.delete("#{Crm::MetaAds::LinksBackfillJob::RUNNING_KEY}:#{connection.id}")
    end

    it 'sem conexão devolve vazio' do
      post "#{path}/insights", headers: auth_headers(admin), as: :json

      expect(response.parsed_body).to eq('insights' => nil)
    end

    it 'agente recebe 403' do
      post "#{path}/insights", headers: auth_headers(agent), as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end
end
