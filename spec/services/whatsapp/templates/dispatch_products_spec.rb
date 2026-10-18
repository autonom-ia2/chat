require 'rails_helper'

# #1418: no disparo, os produtos escolhidos seguem no catálogo da WABA da caixa e à venda; senão a campanha para inteira,
# com o motivo e o nome do produto (decisão do Rodrigo, 14/10/2026: "Pausar e avisar").
RSpec.describe Whatsapp::Templates::DispatchProducts do
  subject(:result) { described_class.new(inbox: inbox, template: template, processed: processed).call }

  let(:inbox) { instance_double(Inbox, id: 7) }
  let(:client) { instance_double(Whatsapp::Templates::CatalogClient) }
  let(:card) { { 'components' => [{ 'type' => 'HEADER', 'format' => 'PRODUCT' }, { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'SPM' }] }] } }
  let(:template) do
    { 'name' => 'cartoes', 'components' => [{ 'type' => 'BODY', 'text' => 'Oi' }, { 'type' => 'CAROUSEL', 'cards' => [card, card] }] }
  end
  let(:processed) { { 'products' => { 'retailer_ids' => %w[a b], 'names' => { 'a' => 'Camiseta', 'b' => 'Tênis' } } } }
  let(:catalog) { Whatsapp::Templates::CatalogClient::Catalog.new(id: 'cat-1', name: 'Loja', product_count: 2) }

  def product(id, available: true)
    Whatsapp::Templates::CatalogClient::Product.new(id: id, name: "Nome #{id}", price: 'R$1', sale_price: '', image_url: '',
                                                    available: available)
  end

  before { allow(Whatsapp::Templates::CatalogClient).to receive(:new).with(inbox: inbox).and_return(client) }

  it 'gives the catalog of the inbox (read fresh, not from the screen cache) when every product is still for sale' do
    allow(client).to receive_messages(catalog: catalog, find: { 'a' => product('a'), 'b' => product('b') })

    expect(result).to be_ok
    expect(client).to have_received(:catalog).with(fresh: true)
    expect(result.catalog_id).to eq('cat-1')
  end

  # #1717: cada envio da campanha grava nome, preço e foto na foto do envio sem perguntar à Meta de novo.
  it 'leaves the products it read for the photo of each send' do
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    allow(client).to receive_messages(catalog: catalog, find: { 'a' => product('a'), 'b' => product('b') })

    result

    expect(Whatsapp::Templates::Enviado::Produtos.guardados(inbox, %w[a b])).to eq(
      'a' => { 'name' => 'Nome a', 'price' => 'R$1', 'image_url' => '' }, 'b' => { 'name' => 'Nome b', 'price' => 'R$1', 'image_url' => '' }
    )
  end

  it 'stops with the name of the product that is out of stock or left the catalog' do
    allow(client).to receive_messages(catalog: catalog, find: { 'a' => product('a', available: false) })

    expect(result).not_to be_ok
    expect(result.reason_code).to eq('template_product_unavailable')
    expect(result.details).to eq(product_ids: %w[a b], product_names: %w[Camiseta Tênis])
  end

  it 'stops when the WABA has no catalog anymore or the token cannot read it' do
    allow(client).to receive(:catalog).and_return(nil)
    expect(result.reason_code).to eq('template_catalog_missing')

    allow(client).to receive(:catalog)
      .and_raise(Whatsapp::Templates::MetaClient::MetaError.new('sem permissão', own_text: true, code: 'permission_denied'))
    expect(described_class.new(inbox: inbox, template: template, processed: processed).call.details).to eq(permission: true)

    allow(client).to receive(:catalog)
      .and_raise(Whatsapp::Templates::MetaClient::MetaError.new('sumiu', own_text: true, code: 'not_found_or_no_access'))
    expect(described_class.new(inbox: inbox, template: template, processed: processed).call.reason_code).to eq('template_catalog_missing')
  end

  it 'lets Meta being down reach the gate (it pauses by the system, never sends blind)' do
    allow(client).to receive(:catalog).and_raise(Whatsapp::Templates::MetaClient::Unreachable)

    expect { result }.to raise_error(Whatsapp::Templates::MetaClient::Unreachable)
  end

  it 'does nothing for a template without products' do
    other = described_class.new(inbox: inbox, template: { 'components' => [{ 'type' => 'BODY' }] }, processed: {}).call

    expect(other).to be_ok
    expect(other.catalog_id).to be_nil
    expect(Whatsapp::Templates::CatalogClient).not_to have_received(:new)
  end
end
