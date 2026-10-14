require 'rails_helper'

# #1418: produtos do catálogo na campanha (um, vários e carrossel de produtos). Formatos e limites da Meta, lidos em
# 14/10/2026: developers.facebook.com/documentation/business-messaging/whatsapp/catalogs/
# {spm,mpm,product-card-carousel}-template-messages.
RSpec.describe Whatsapp::Templates::ProductParams do
  def template(*components, language: 'pt_BR')
    { 'name' => 'vitrine', 'language' => language, 'components' => components }
  end

  let(:body) { { 'type' => 'BODY', 'text' => 'Oi {{1}}' } }
  let(:um) do
    template({ 'type' => 'HEADER', 'format' => 'PRODUCT' }, body, { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'SPM', 'text' => 'Ver' }] })
  end
  let(:varios) do
    template({ 'type' => 'HEADER', 'format' => 'TEXT', 'text' => 'Novidades' }, body,
             { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'MPM', 'text' => 'Ver itens' }] })
  end
  let(:card) { { 'components' => [{ 'type' => 'HEADER', 'format' => 'PRODUCT' }, { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'SPM' }] }] } }
  let(:carrossel) { template(body, { 'type' => 'CAROUSEL', 'cards' => [card, card] }) }
  let(:media_carousel) do
    template(body, { 'type' => 'CAROUSEL', 'cards' => [{ 'components' => [{ 'type' => 'HEADER', 'format' => 'IMAGE' }] }] * 2 })
  end

  def ids(count)
    Array.new(count) { |index| "sku-#{index}" }
  end

  describe '.kind' do
    it 'reads the kind from the structure: SPM, MPM or carousel of product cards' do
      expect([um, varios, carrossel].map { |item| described_class.kind(item) }).to eq(%w[um varios carrossel])
    end

    it 'is nil for any other template, including the carousel of photos' do
      expect(described_class.kind(media_carousel)).to be_nil
      expect(described_class.kind(template(body))).to be_nil
      expect(described_class.kind(nil)).to be_nil
    end
  end

  describe '.ready?' do
    it 'asks 1 product for one, 1 to 30 for several and 2 to 10 for the carousel' do
      expect(described_class.ready?(um, { 'products' => { 'retailer_ids' => ids(1) } })).to be(true)
      expect(described_class.ready?(um, { 'products' => { 'retailer_ids' => ids(2) } })).to be(false)
      expect(described_class.ready?(varios, { 'products' => { 'retailer_ids' => ids(30) } })).to be(true)
      expect(described_class.ready?(varios, { 'products' => { 'retailer_ids' => ids(31) } })).to be(false)
      expect(described_class.ready?(carrossel, { 'products' => { 'retailer_ids' => ids(1) } })).to be(false)
      expect(described_class.ready?(carrossel, { 'products' => { 'retailer_ids' => ids(10) } })).to be(true)
      expect(described_class.ready?(carrossel, {})).to be(false)
    end

    it 'ignores blank and repeated codes' do
      expect(described_class.ready?(carrossel, { 'products' => { 'retailer_ids' => ['a', ' a ', '', nil] } })).to be(false)
    end
  end

  describe '.normalize!' do
    it 'keeps only the clean codes, in the chosen order, with the names shown in the pause message' do
      processed = { 'products' => { 'retailer_ids' => [' b ', 'a', 'b'], 'names' => { 'a' => 'Camiseta', 'b' => 'Tênis', 'z' => 'x' },
                                    'catalog_id' => 'vindo-da-tela' } }
      expect(described_class.normalize!(processed, carrossel)['products'])
        .to eq('retailer_ids' => %w[b a], 'names' => { 'b' => 'Tênis', 'a' => 'Camiseta' })
    end

    it 'refuses a product template without the right number of products' do
      expect { described_class.normalize!({}, um) }.to raise_error(Whatsapp::Templates::HeaderMedia::Invalid, 'products_required')
      expect { described_class.normalize!({ 'products' => { 'retailer_ids' => ids(11) } }, carrossel) }
        .to raise_error(Whatsapp::Templates::HeaderMedia::Invalid, 'products_count')
    end

    it 'drops the key from a template without products' do
      expect(described_class.normalize!({ 'body' => { '1' => 'Ana' }, 'products' => { 'retailer_ids' => ['a'] } }, template(body)))
        .to eq('body' => { '1' => 'Ana' })
    end
  end

  describe '.components' do
    let(:catalog) { '194836987003835' }

    it 'one product: the product header with the catalog of the inbox' do
      result = described_class.components(um, { 'products' => { 'retailer_ids' => ['sku-1'], 'catalog_id' => catalog } })
      expect(result).to eq(
        header: [{ type: 'header', parameters: [{ type: 'product', product: { product_retailer_id: 'sku-1', catalog_id: catalog } }] }],
        after_body: [], buttons: []
      )
    end

    it 'several: the MPM button with the first product as the photo and one section with the fixed title' do
      result = described_class.components(varios, { 'products' => { 'retailer_ids' => %w[a b], 'catalog_id' => catalog } })
      expect(result[:buttons]).to eq(
        [{ type: 'button', sub_type: 'mpm', index: 0,
           parameters: [{ type: 'action', action: { thumbnail_product_retailer_id: 'a',
                                                    sections: [{ title: 'Escolhidos para você',
                                                                 product_items: [{ product_retailer_id: 'a' },
                                                                                 { product_retailer_id: 'b' }] }] } }] }]
      )
    end

    it 'uses the title in the language of the template' do
      english = varios.merge('language' => 'en_US')
      result = described_class.components(english, { 'products' => { 'retailer_ids' => ['a'] } })
      expect(result[:buttons].first.dig(:parameters, 0, :action, :sections, 0, :title)).to eq('Picked for you')
    end

    it 'carousel: one card per product, in the chosen order' do
      result = described_class.components(carrossel, { 'products' => { 'retailer_ids' => %w[a b c], 'catalog_id' => catalog } })
      expect(result[:after_body]).to eq(
        [{ type: 'carousel', cards: %w[a b c].each_with_index.map do |id, index|
          { card_index: index,
            components: [{ type: 'header', parameters: [{ type: 'product', product: { product_retailer_id: id, catalog_id: catalog } }] }] }
        end }]
      )
    end

    it 'adds nothing without products or for another template' do
      expect(described_class.components(um, {})).to eq(header: [], after_body: [], buttons: [])
      expect(described_class.components(template(body), { 'products' => { 'retailer_ids' => ['a'] } }))
        .to eq(header: [], after_body: [], buttons: [])
    end
  end
end
