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
end

RSpec.configure do |config|
  config.include MetaAdsHelpers
end
