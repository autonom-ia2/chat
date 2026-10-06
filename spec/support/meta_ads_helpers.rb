# Nomes das campanhas da Meta (#1034): credencial de teste e stubs da Graph API. Nunca rede real.
module MetaAdsHelpers
  TEST_TOKEN = 'EAAGtesttoken1234567890abcdefSEGREDO'.freeze

  def meta_graph_url(path = '')
    version = GlobalConfigService.load('WHATSAPP_API_VERSION', Meta::ConversionsApiClient::DEFAULT_API_VERSION)
    "#{Meta::ConversionsApiClient::BASE_URI}/#{version}/#{path}"
  end

  def create_meta_ads_connection(account, status: 'active', token: TEST_TOKEN)
    enable_test_encryption!
    Crm::MetaAdsConnection.create!(account: account, access_token: token, status: status)
  end

  # Um objeto por chamada: GET /<id>?fields=… (o lote ?ids= saiu na Graph v26.0, #1043).
  def stub_meta_object(id:, fields:, body:, status: 200, token: TEST_TOKEN)
    stub_request(:get, meta_graph_url(id.to_s))
      .with(query: { fields: fields }, headers: { 'Authorization' => "Bearer #{token}" })
      .to_return(status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  # Qualquer leitura de objeto da Graph (tudo menos /me/...). O WebMock entrega a URI normalizada,
  # com a porta, então a comparação é por host e caminho.
  def meta_object_requests
    graph = URI(meta_graph_url)
    a_request(:get, ->(uri) { uri.host == graph.host && uri.path.start_with?(graph.path) && uri.path.exclude?('/me/') })
  end

  def meta_graph_error(code, message = 'Erro da Meta')
    { error: { message: message, type: 'OAuthException', code: code } }
  end

  # Insights (#1073): conexão com conta de anúncios escolhida, linha como a Meta devolve e stub do GET.
  def create_meta_ads_insights_connection(account, ad_account_id: '2196424464528988', timezone: 'America/Sao_Paulo')
    connection = create_meta_ads_connection(account)
    connection.update!(ad_account_id: ad_account_id, ad_account_name: 'CA - Placement Seguros', verified_at: Time.current,
                       ad_account_timezone: timezone)
    connection
  end

  def meta_insights_row(ad_id: '120254710067060999', date: '2026-10-06', spend: '42.50', conversations: '3', **extra)
    {
      ad_id: ad_id, ad_name: 'Video 2', adset_id: '120254710067060777', adset_name: 'Conjunto 60+',
      campaign_id: '120254710067060416', campaign_name: 'Viagem EUA', account_currency: 'BRL',
      spend: spend, impressions: '1500', reach: '1200', frequency: '1.25', inline_link_clicks: '40',
      actions: [{ action_type: 'onsite_conversion.messaging_conversation_started_7d', value: conversations, '7d_click': conversations }],
      date_start: date, date_stop: date
    }.merge(extra)
  end

  # response: status (200) e headers extras da resposta.
  def stub_meta_insights(ad_account_id, date_preset:, rows:, breakdowns: nil, **response)
    status = response.fetch(:status, 200)
    query = { 'date_preset' => date_preset, 'level' => 'ad', 'time_increment' => '1' }
    query['breakdowns'] = breakdowns if breakdowns
    query['fields'] = breakdowns ? Crm::MetaAds::Insights::Query::PLACEMENT_FIELDS : Crm::MetaAds::Insights::Query::AD_FIELDS
    body = status == 200 ? { data: rows } : rows
    stub_request(:get, meta_graph_url("act_#{ad_account_id}/insights"))
      .with(query: hash_including(query), headers: { 'Authorization' => "Bearer #{TEST_TOKEN}" })
      .to_return(status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' }.merge(response.fetch(:headers, {})))
  end
end

RSpec.configure do |config|
  config.include MetaAdsHelpers
end

# Conta com Anúncios da Meta ligado e conexão com conta de anúncios (#1073). Solta travas e pausas no Redis,
# que não volta com a transação do exemplo.
RSpec.shared_context 'with a meta ads insights connection' do
  let(:account) { create(:account) }
  let(:connection) { create_meta_ads_insights_connection(account) }
  let(:ad_account_id) { connection.ad_account_id }

  before { account.enable_features!('meta_ads_hub') }

  after do
    %w[today recent].each { |scope| Crm::MetaAds::Insights::Refresh.release(connection.id, scope) }
    Crm::MetaAds::Insights::Backfill.release(connection.id)
    Redis::Alfred.delete(Crm::MetaAds::Insights::Usage.key(ad_account_id))
  end
end
