require 'rails_helper'

# #1418: a Nova campanha lê o catálogo de produtos da WABA da caixa (Graph falsa). Só com a flag
# `whatsapp_campaign_products`; quem vê os modelos vê os produtos; a WABA e o catálogo são sempre os da caixa.
RSpec.describe 'Api::V1::Accounts::Inboxes::WhatsappCatalogs', type: :request do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false,
                              message_templates: [])
  end
  let(:inbox) { channel.inbox }
  let(:base) { "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/whatsapp_catalog" }
  let(:graph) { 'https://graph.facebook.com/v22.0' }
  let(:json) { { 'Content-Type' => 'application/json' } }

  before do
    account.enable_features!('whatsapp_campaign_products')
    allow_any_instance_of(Whatsapp::Templates::CatalogClient).to receive(:sleep) # rubocop:disable RSpec/AnyInstance
  end

  def call(path, params = {}, user: admin)
    get path, params: params, headers: user.create_new_auth_token, as: :json
  end

  def stub_catalogs(data)
    stub_request(:get, "#{graph}/#{channel.waba_id}/product_catalogs").with(query: hash_including({}))
                                                                      .to_return(status: 200, headers: json, body: { data: data }.to_json)
  end

  it 'answers 404 without the account flag, before any call to Meta' do
    account.disable_features!('whatsapp_campaign_products')

    call(base)

    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body['error']).to eq('feature_disabled')
    expect(a_request(:get, ->(uri) { uri.host == 'graph.facebook.com' })).not_to have_been_made
  end

  it 'refuses who cannot see the templates' do
    call(base, user: agent)

    expect(response).to have_http_status(:unauthorized)
  end

  it 'gives the name and the size of the catalog, or null without one' do
    stub_catalogs([{ id: 'cat-1', name: 'Loja Hub2you', product_count: 9 }])
    call(base)
    expect(response.parsed_body).to eq('catalog' => { 'name' => 'Loja Hub2you', 'product_count' => 9 })
  end

  it 'gives null when the WABA has no catalog' do
    stub_catalogs([])
    call(base)
    expect(response.parsed_body).to eq('catalog' => nil)
  end

  it 'lists the products of the inbox catalog with the search and the next page' do
    stub_catalogs([{ id: 'cat-1', name: 'Loja', product_count: 1 }])
    stub_request(:get, "#{graph}/cat-1/products")
      .with(query: hash_including('filter' => { name: { i_contains: 'tenis' } }.to_json, 'after' => 'c1'))
      .to_return(status: 200, headers: json,
                 body: { data: [{ retailer_id: 'tenis', name: 'Tênis', price: 'R$299,90', image_url: 'https://cdn/t.jpg',
                                  availability: 'in stock' }],
                         paging: { cursors: { after: 'c2' }, next: 'https://graph/next' } }.to_json)

    call("#{base}/products", { q: 'tenis', after: 'c1' })

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq(
      'payload' => [{ 'id' => 'tenis', 'name' => 'Tênis', 'price' => 'R$299,90', 'image_url' => 'https://cdn/t.jpg', 'available' => true }],
      'meta' => { 'after' => 'c2' }
    )
  end

  it 'says the catalog is missing and the permission problem in the language of the account' do
    stub_catalogs([])
    call("#{base}/products")
    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body['error']).to eq('catalog_missing')

    stub_request(:get, "#{graph}/#{channel.waba_id}/product_catalogs").with(query: hash_including({}))
                                                                      .to_return(status: 403, headers: json, body: { error: { code: 10 } }.to_json)
    call(base)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to include('error' => 'catalog_permission_denied',
                                            'message' => I18n.t('whatsapp_templates.errors.catalog_permission_denied', locale: :pt_BR))
  end

  it 'never reads an inbox of another account' do
    other = create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)

    call("/api/v1/accounts/#{account.id}/inboxes/#{other.inbox.id}/whatsapp_catalog")

    expect(response).to have_http_status(:not_found)
  end
end
