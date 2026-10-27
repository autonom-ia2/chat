require 'rails_helper'

# Reautorização da caixa do Instagram a partir de um cartão de Anúncios (#2196): o escopo a mais sai do servidor pela
# tela de volta (EXTRA_SCOPES, nunca do front), só com a flag dela ligada, e o state guarda para onde a pessoa volta.
# Pela tela da caixa, o login continua pedindo só REQUIRED_SCOPES.
RSpec.describe 'Instagram reauthorization from Meta ads (#2196)', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:path) { "/api/v1/accounts/#{account.id}/instagram/authorization" }
  let(:inbox) { create(:channel_instagram, account: account).inbox }

  around do |example|
    with_modified_env('FRONTEND_URL' => 'https://autonomia.example') { example.run }
  end

  before do
    account.enable_features!(:channel_instagram, :meta_ads_comentarios_instagram)
    allow(GlobalConfig).to receive(:get_value).and_call_original
    allow(GlobalConfig).to receive(:get_value).with('DISABLE_META_INBOX_CREATION').and_return(false)
    allow(GlobalConfigService).to receive(:load).and_call_original
    allow(GlobalConfigService).to receive(:load).with('INSTAGRAM_APP_SECRET', nil).and_return('synthetic_secret')
  end

  def authorize(params)
    post path, params: params, headers: administrator.create_new_auth_token, as: :json
  end

  def url_parts
    query = Rack::Utils.parse_query(URI.parse(response.parsed_body.fetch('url')).query)
    [query['scope'].split(','), JWT.decode(query.fetch('state'), 'synthetic_secret', true, algorithm: 'HS256').first]
  end

  it 'pede a permissão de comentários e guarda a volta ao anúncio' do
    authorize(inbox_id: inbox.id, return_to: 'comentarios_ig', ad_id: '120254710382770416')

    expect(response).to have_http_status(:ok)
    scopes, state = url_parts
    expect(scopes).to eq(Instagram::IntegrationHelper::REQUIRED_SCOPES + %w[instagram_business_manage_comments])
    expect(state).to include('inbox_id' => inbox.id, 'return_to' => 'comentarios_ig', 'ad_id' => '120254710382770416')
  end

  it 'reautorização pela caixa continua só com os escopos de sempre' do
    authorize(inbox_id: inbox.id, return_to: 'inbox')

    scopes, state = url_parts
    expect(scopes).to eq(Instagram::IntegrationHelper::REQUIRED_SCOPES)
    expect(state).not_to have_key('ad_id')
  end

  it 'recusa tela desconhecida, flag desligada, ad_id que não é número e volta a Anúncios sem caixa' do
    [{ inbox_id: inbox.id, return_to: 'outra_tela' },
     { inbox_id: inbox.id, return_to: 'comentarios_ig', ad_id: '12?x=1' },
     { return_to: 'comentarios_ig' }].each do |params|
      authorize(params)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    account.disable_features!(:meta_ads_comentarios_instagram)
    authorize(inbox_id: inbox.id, return_to: 'comentarios_ig')
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
