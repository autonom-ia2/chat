require 'rails_helper'

# #1418: o catálogo de produtos conectado à WABA da caixa, lido com o token da caixa (Graph falsa, WebMock).
# Fonte oficial, lida em 14/10/2026: developers.facebook.com/docs/graph-api/reference/whatsapp-business-account/
# product_catalogs/ e developers.facebook.com/docs/marketing-api/reference/product-catalog/products/.
RSpec.describe Whatsapp::Templates::CatalogClient do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false,
                              message_templates: [])
  end
  let(:inbox) { channel.inbox }
  let(:graph) { 'https://graph.facebook.com/v22.0' }
  let(:catalogs_url) { "#{graph}/#{channel.waba_id}/product_catalogs" }
  let(:products_url) { "#{graph}/cat-1/products" }
  let(:json) { { 'Content-Type' => 'application/json' } }
  let(:client) { described_class.new(inbox: inbox) }
  let(:token) { channel.template_access_token }

  # O teste usa :null_store; aqui a guarda do catálogo precisa existir.
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }

  before do
    allow(client).to receive(:sleep)
    allow(Rails).to receive(:cache).and_return(cache)
  end

  def stub_catalogs(data, status: 200)
    stub_request(:get, catalogs_url).with(query: hash_including({}))
                                    .to_return(status: status, headers: json, body: (status == 200 ? { data: data } : data).to_json)
  end

  def product(id, name, availability: 'in stock')
    { 'retailer_id' => id, 'name' => name, 'price' => 'R$59,90', 'image_url' => "https://cdn.loja.com/#{id}.jpg",
      'availability' => availability, 'id' => "meta-#{id}" }
  end

  it 'only serves a WhatsApp Cloud inbox with the WABA saved' do
    channel.update_columns(provider_config: channel.provider_config.except('business_account_id')) # rubocop:disable Rails/SkipsModelValidations
    expect { described_class.new(inbox: inbox.reload) }.to raise_error(Whatsapp::Templates::MetaClient::Unsupported)
  end

  describe '#catalog' do
    it 'reads the catalog connected to the WABA of the inbox, with the inbox token in the header (never in the URL)' do
      request = stub_catalogs([{ 'id' => 'cat-1', 'name' => 'Loja', 'product_count' => 9 }])

      expect(client.catalog).to eq(described_class::Catalog.new(id: 'cat-1', name: 'Loja', product_count: 9))
      expect(request.with(headers: { 'Authorization' => "Bearer #{token}" })).to have_been_made.once
      expect(a_request(:get, catalogs_url).with(query: hash_including({})) { |req| req.uri.to_s.include?(token) }).not_to have_been_made
    end

    it 'is nil when the WABA has no catalog and is cached for a few minutes' do
      request = stub_catalogs([])

      2.times { expect(client.catalog).to be_nil }
      expect(request).to have_been_made.once
    end

    it 'says permission_denied by the Meta code, without the token in the message' do
      stub_catalogs({ error: { code: 10, message: "Sem permissão #{token}" } }, status: 403)

      expect { client.catalog }.to raise_error(Whatsapp::Templates::MetaClient::MetaError) { |error|
        expect(error.code).to eq('permission_denied')
        expect(error.message).not_to include(token)
      }
    end
  end

  describe '#products' do
    before { stub_catalogs([{ 'id' => 'cat-1', 'name' => 'Loja', 'product_count' => 2 }]) }

    it 'lists only approved products, searching by name, with the next page cursor' do
      request = stub_request(:get, products_url)
                .with(query: hash_including('return_only_approved_products' => 'true', 'filter' => { name: { i_contains: 'tênis' } }.to_json))
                .to_return(status: 200, headers: json,
                           body: { data: [product('tenis', 'Tênis preto'), product('fone', 'Fone', availability: 'out of stock')],
                                   paging: { cursors: { after: 'c2' }, next: 'https://graph/next' } }.to_json)

      page = client.products(search: ' tênis ')

      expect(request).to have_been_made
      expect(page.after).to eq('c2')
      expect(page.products.map(&:to_h)).to eq(
        [{ id: 'tenis', name: 'Tênis preto', price: 'R$59,90', image_url: 'https://cdn.loja.com/tenis.jpg', available: true },
         { id: 'fone', name: 'Fone', price: 'R$59,90', image_url: 'https://cdn.loja.com/fone.jpg', available: false }]
      )
    end

    it 'has no next page when Meta sends no next link' do
      stub_request(:get, products_url).with(query: hash_including({}))
                                      .to_return(status: 200, headers: json, body: { data: [], paging: { cursors: { after: 'x' } } }.to_json)

      expect(client.products.after).to be_nil
    end

    it 'raises NoCatalog when the WABA has no catalog' do
      cache.clear
      stub_catalogs([])

      expect { client.products }.to raise_error(described_class::NoCatalog)
    end
  end

  describe '#find' do
    it 'reads the chosen products by their codes, only the approved ones' do
      stub_catalogs([{ 'id' => 'cat-1', 'name' => 'Loja', 'product_count' => 2 }])
      stub_request(:get, products_url)
        .with(query: hash_including('filter' => { retailer_id: { is_any: %w[a b] } }.to_json, 'return_only_approved_products' => 'true'))
        .to_return(status: 200, headers: json, body: { data: [product('a', 'Camiseta')] }.to_json)

      found = client.find(%w[a b])

      expect(found.keys).to eq(['a'])
      expect(found['a'].available).to be(true)
    end

    # Enum `availability` da Meta (developers.facebook.com/docs/marketing-api/reference/product-item/, lido em 15/10/2026).
    it 'counts in stock, available for order and preorder as for sale, and nothing else' do
      stub_catalogs([{ 'id' => 'cat-1', 'name' => 'Loja', 'product_count' => 8 }])
      values = ['in stock', 'available for order', 'preorder', 'out of stock', 'discontinued', 'pending', 'mark_as_sold',
                'mark_as_expired']
      stub_request(:get, products_url).with(query: hash_including({}))
                                      .to_return(status: 200, headers: json,
                                                 body: { data: values.map { |value| product(value, value, availability: value) } }.to_json)

      sellable = client.find(values).select { |_id, item| item.available }.keys

      expect(sellable).to eq(['in stock', 'available for order', 'preorder'])
    end
  end

  # #1717: a foto do envio não pode segurar o envio esperando a Meta.
  describe 'consulta rápida (foto do envio)' do
    let(:client) { described_class.new(inbox: inbox, timeout: 2, insistir: false) }

    it 'pergunta com o prazo pedido e uma tentativa só' do
      allow(HTTParty).to receive(:get).and_raise(Net::ReadTimeout)

      expect { client.catalog }.to raise_error(Net::ReadTimeout)
      expect(HTTParty).to have_received(:get).once.with(anything, hash_including(timeout: 2))
      expect(client).not_to have_received(:sleep)
    end

    it 'o cliente normal continua insistindo três vezes com o prazo de sempre' do
      normal = described_class.new(inbox: inbox)
      allow(normal).to receive(:sleep)
      allow(HTTParty).to receive(:get).and_raise(Net::ReadTimeout)

      expect { normal.catalog }.to raise_error(Whatsapp::Templates::MetaClient::Unreachable)
      expect(HTTParty).to have_received(:get).exactly(3).times.with(anything, hash_including(timeout: described_class::REQUEST_TIMEOUT))
    end
  end
end
