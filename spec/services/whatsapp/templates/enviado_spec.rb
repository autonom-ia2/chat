require 'rails_helper'

# #1717: a foto do que o envio de um modelo levou (contrato versão 1, combinado com o Frontend geral em 16/10/2026).
# Os modelos estão no formato que a Meta devolve em GET /{waba}/message_templates (documentação oficial lida em
# 13 e 14/10/2026: marketing-templates/{limited-time-offer,coupon,media-card-carousel}-templates e
# catalogs/{spm,mpm,product-card-carousel}-template-messages).
RSpec.describe Whatsapp::Templates::Enviado do
  subject(:foto) { described_class.montar(template: template, processed: processed, inbox: inbox, catalogo: catalogo) }

  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false,
                              message_templates: [])
  end
  let(:inbox) { channel.inbox }
  let(:catalogo) { :consultar }
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }
  let(:graph) { 'https://graph.facebook.com/v22.0' }
  let(:json) { { 'Content-Type' => 'application/json' } }

  before { allow(Rails).to receive(:cache).and_return(cache) }

  def approved(name, *components)
    { 'name' => name, 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'MARKETING',
      'parameter_format' => 'POSITIONAL', 'components' => components }
  end

  def stub_catalog(products)
    catalogs = { data: [{ id: 'cat-1' }] }.to_json
    stub_request(:get, "#{graph}/#{channel.waba_id}/product_catalogs").with(query: hash_including({}))
                                                                      .to_return(status: 200, headers: json, body: catalogs)
    stub_request(:get, "#{graph}/cat-1/products").with(query: hash_including({}))
                                                 .to_return(status: 200, headers: json, body: { data: products }.to_json)
  end

  def meta_product(id, name, price, image)
    { 'retailer_id' => id, 'name' => name, 'price' => price, 'image_url' => image, 'availability' => 'in stock', 'id' => "meta-#{id}" }
  end

  describe 'oferta por tempo limitado com cupom e link com variável' do
    let(:template) do
      approved('oferta_relampago',
               { 'type' => 'HEADER', 'format' => 'IMAGE', 'example' => { 'header_handle' => ['4::aW1h'] } },
               { 'type' => 'LIMITED_TIME_OFFER', 'limited_time_offer' => { 'text' => 'Só hoje!', 'has_expiration' => true } },
               { 'type' => 'BODY', 'text' => 'Oi {{1}}, use o cupom {{2}}.', 'example' => { 'body_text' => [%w[Ana PROMO25]] } },
               { 'type' => 'BUTTONS', 'buttons' => [
                 { 'type' => 'COPY_CODE', 'text' => 'Copiar código', 'example' => 'PROMO25' },
                 { 'type' => 'URL', 'text' => 'Ver proposta', 'url' => 'https://loja.com.br/b/{{1}}', 'example' => ['https://loja.com.br/b/x'] }
               ] })
    end
    let(:processed) do
      { 'header' => { 'media_url' => 'https://loja.com.br/topo.png', 'media_type' => 'image' }, 'body' => { '1' => 'Ana', '2' => 'PROMO25' },
        'limited_time_offer' => { 'expiration_time_ms' => 1_760_659_200_000 },
        'buttons' => [{ 'type' => 'copy_code', 'parameter' => 'SEGREDO9' }, { 'type' => 'url', 'parameter' => 'AB3K' }] }
    end

    it 'grava a validade em segundos e os botões; o código do cupom nunca entra' do
      expect(foto).to eq(
        'versao' => 1,
        'oferta' => { 'expira_em' => 1_760_659_200 },
        'botoes' => [{ 'tipo' => 'copy_code', 'texto' => 'Copiar código' },
                     { 'tipo' => 'url', 'texto' => 'Ver proposta', 'url' => 'https://loja.com.br/b/AB3K' }]
      )
      expect(foto.to_json).not_to include('SEGREDO9')
      expect(foto.to_json).not_to include('processed_params')
    end

    it 'sem a validade no envio, não há oferta' do
      processed.delete('limited_time_offer')

      expect(foto).not_to have_key('oferta')
    end

    it 'link com variável sem valor fica sem endereço (nunca "{{1}}" na tela)' do
      processed['buttons'][1] = { 'type' => 'url', 'parameter' => '' }

      expect(foto['botoes'].last).to eq('tipo' => 'url', 'texto' => 'Ver proposta', 'url' => nil)
    end

    it 'link que não é http(s) vira nil' do
      template['components'].last['buttons'][1]['url'] = 'javascript:alert({{1}})'

      expect(foto['botoes'].last['url']).to be_nil
    end
  end

  describe 'resposta rápida e link fixo (aviso do agendamento)' do
    let(:template) do
      approved('agendamento_ao_marcar_v2', { 'type' => 'BODY', 'text' => 'Oi {{1}}, marcado para {{2}}.' },
               { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'URL', 'text' => 'Ver meu horário', 'url' => 'https://app.example.com/b/{{1}}' },
                                                    { 'type' => 'QUICK_REPLY', 'text' => 'Parar avisos' },
                                                    { 'type' => 'PHONE_NUMBER', 'text' => 'Ligar', 'phone_number' => '+5511999990000' }] })
    end
    let(:processed) do
      { 'body' => { '1' => 'Marcos', '2' => '20/10 às 10:00' },
        'buttons' => [{ 'type' => 'url', 'parameter' => 'X9Y8' }, { 'type' => 'quick_reply', 'payload' => 'stop_notices' }] }
    end

    it 'leva o texto de cada botão e o link resolvido; nada de payload nem telefone' do
      expect(foto['botoes']).to eq([{ 'tipo' => 'url', 'texto' => 'Ver meu horário', 'url' => 'https://app.example.com/b/X9Y8' },
                                    { 'tipo' => 'quick_reply', 'texto' => 'Parar avisos' },
                                    { 'tipo' => 'phone_number', 'texto' => 'Ligar' }])
      expect(foto.to_json).not_to include('stop_notices', '5511999990000')
    end
  end

  describe 'um produto (SPM)' do
    let(:template) do
      approved('produto_destaque', { 'type' => 'HEADER', 'format' => 'PRODUCT' }, { 'type' => 'BODY', 'text' => 'Olha esse!' },
               { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'SPM', 'text' => 'Ver' }] })
    end
    let(:processed) { { 'products' => { 'retailer_ids' => ['SKU1'], 'catalog_id' => 'cat-1' } } }

    it 'grava nome, preço e foto do catálogo da caixa na hora do envio' do
      stub_catalog([meta_product('SKU1', 'Tênis Corrida', 'R$ 299,90', 'https://cdn.loja.com.br/sku1.jpg')])

      expect(foto).to eq('versao' => 1,
                         'produto' => { 'retailer_id' => 'SKU1', 'nome' => 'Tênis Corrida', 'preco' => 'R$ 299,90',
                                        'foto_url' => 'https://cdn.loja.com.br/sku1.jpg' },
                         'botoes' => [{ 'tipo' => 'spm', 'texto' => 'Ver' }])
    end

    it 'a Meta fora do ar: só o retailer_id, numa tentativa só, no catálogo que o envio já leva' do
      stub_request(:get, "#{graph}/cat-1/products").with(query: hash_including({})).to_timeout

      expect(foto['produto']).to eq('retailer_id' => 'SKU1')
      expect(a_request(:get, "#{graph}/cat-1/products").with(query: hash_including({}))).to have_been_made.once
      expect(a_request(:get, "#{graph}/#{channel.waba_id}/product_catalogs").with(query: hash_including({}))).not_to have_been_made
    end

    it 'sem o catálogo no envio (conversa), lê o catálogo da WABA da caixa' do
      processed['products'].delete('catalog_id')
      stub_catalog([meta_product('SKU1', 'Tênis', 'R$ 1', 'https://cdn.loja.com.br/sku1.jpg')])

      expect(foto.dig('produto', 'nome')).to eq('Tênis')
      expect(a_request(:get, "#{graph}/#{channel.waba_id}/product_catalogs").with(query: hash_including({}))).to have_been_made.once
    end

    it 'foto de link assinado que expira (S3) vira nil' do
      stub_catalog([meta_product('SKU1', 'Tênis', 'R$ 1', 'https://loja.s3.amazonaws.com/sku1.jpg?X-Amz-Expires=3600&X-Amz-Signature=ab')])

      expect(foto.dig('produto', 'foto_url')).to be_nil
    end

    it 'foto temporária da Meta ou sem https vira nil' do
      stub_catalog([meta_product('SKU1', 'Tênis', 'R$ 1', 'https://scontent.xx.fbcdn.net/v/t45/sku1.jpg?oe=6720')])
      expect(foto.dig('produto', 'foto_url')).to be_nil

      cache.clear
      stub_catalog([meta_product('SKU1', 'Tênis', 'R$ 1', 'http://cdn.loja.com.br/sku1.jpg')])
      expect(described_class.montar(template: template, processed: processed, inbox: inbox).dig('produto', 'foto_url')).to be_nil
    end
  end

  describe 'vários produtos (MPM) e carrossel de produtos' do
    let(:mpm) do
      approved('volte_carrinho', { 'type' => 'HEADER', 'format' => 'TEXT', 'text' => 'Esqueceu algo?' },
               { 'type' => 'BODY', 'text' => 'Seus itens' }, { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'MPM', 'text' => 'Ver itens' }] })
    end
    let(:product_card) do
      { 'components' => [{ 'type' => 'HEADER', 'format' => 'PRODUCT' },
                         { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'SPM', 'text' => 'Ver' }] }] }
    end
    let(:carrossel) do
      approved('vitrine', { 'type' => 'BODY', 'text' => 'Vitrine' }, { 'type' => 'CAROUSEL', 'cards' => [product_card, product_card] })
    end
    let(:template) { mpm }
    let(:processed) { { 'products' => { 'retailer_ids' => %w[SKU1 SKU2], 'catalog_id' => 'cat-1' } } }
    let(:catalogo) { :guardado }

    before do
      camiseta = Whatsapp::Templates::CatalogClient::Product.new(id: 'SKU1', name: 'Camiseta', price: 'R$ 59,90', sale_price: '',
                                                                 image_url: 'https://cdn.loja.com.br/1.jpg', available: true)
      Whatsapp::Templates::Enviado::Produtos.lembrar(inbox, [camiseta])
    end

    it 'MPM: a lista na ordem escolhida, com o que o disparo já leu; o que ele não leu fica só com o código' do
      expect(foto['produtos']).to eq([{ 'retailer_id' => 'SKU1', 'nome' => 'Camiseta', 'preco' => 'R$ 59,90',
                                        'foto_url' => 'https://cdn.loja.com.br/1.jpg' },
                                      { 'retailer_id' => 'SKU2' }])
      expect(foto['botoes']).to eq([{ 'tipo' => 'mpm', 'texto' => 'Ver itens' }])
      expect(a_request(:get, /graph.facebook.com/)).not_to have_been_made
    end

    it 'carrossel de produtos: cada cartão é um produto e vai em produtos (sem cartoes)' do
      foto = described_class.montar(template: carrossel, processed: processed, inbox: inbox, catalogo: :guardado)

      expect(foto['produtos'].pluck('retailer_id')).to eq(%w[SKU1 SKU2])
      expect(foto).not_to have_key('cartoes')
    end
  end

  describe 'carrossel de mídia' do
    let(:card) do
      lambda do |text|
        { 'components' => [{ 'type' => 'HEADER', 'format' => 'IMAGE', 'example' => { 'header_handle' => ['4::aW1h'] } },
                           { 'type' => 'BODY', 'text' => text, 'example' => { 'body_text' => [['15OFF']] } },
                           { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'QUICK_REPLY', 'text' => 'Quero esse' },
                                                                { 'type' => 'URL', 'text' => 'Comprar', 'url' => 'https://loja.com.br/p?promo={{1}}',
                                                                  'example' => ['https://loja.com.br/p?promo=15OFF'] }] }] }
      end
    end
    let(:template) do
      approved('carrossel_ofertas', { 'type' => 'BODY', 'text' => 'Ofertas da semana' },
               { 'type' => 'CAROUSEL', 'cards' => [card.call('Limão siciliano, cupom {{1}}'), card.call('Laranja, cupom {{1}}')] })
    end
    let(:blob) do
      ActiveStorage::Blob.create_and_upload!(io: StringIO.new('png'), filename: 'limao.png', content_type: 'image/png',
                                             metadata: { 'account_id' => account.id })
    end
    let(:processed) do
      { 'body' => {},
        'carousel' => { 'cards' => [
          { 'header' => { 'media_url' => 'https://s3.example.com/limao.png?X-Amz-Expires=86400', 'media_type' => 'image',
                          'media_name' => 'limao.png', 'media_signed_id' => blob.signed_id },
            'body' => { '1' => '15OFF' },
            'buttons' => [{ 'type' => 'quick_reply', 'payload' => 'limao' }, { 'type' => 'url', 'parameter' => '15OFF' }] },
          { 'header' => { 'media_url' => 'https://lookaside.fbsbx.com/whatsapp_business/attachments/?mid=1', 'media_type' => 'image' },
            'body' => { '1' => '' },
            'buttons' => [nil, { 'type' => 'url', 'parameter' => '10OFF' }] }
        ] } }
    end

    it 'mídia só do nosso armazenamento (endereço permanente), texto com os valores e botões de cada cartão' do
      cartoes = foto['cartoes']

      expect(cartoes.first['midia']).to eq('tipo' => 'image', 'url' => Rails.application.routes.url_helpers.rails_blob_url(blob))
      expect(cartoes.first['texto']).to eq('Limão siciliano, cupom 15OFF')
      expect(cartoes.first['botoes']).to eq([{ 'tipo' => 'quick_reply', 'texto' => 'Quero esse' },
                                             { 'tipo' => 'url', 'texto' => 'Comprar', 'url' => 'https://loja.com.br/p?promo=15OFF' }])
      expect(cartoes.last['midia']).to eq('tipo' => 'image', 'url' => nil)
      expect(cartoes.last['texto']).to be_nil
      expect(cartoes.last['botoes'].last['url']).to eq('https://loja.com.br/p?promo=10OFF')
      expect(foto.to_json).not_to include('fbsbx', 'X-Amz', 'payload')
    end

    it 'arquivo de outra conta não vira endereço' do
      alheio = ActiveStorage::Blob.create_and_upload!(io: StringIO.new('png'), filename: 'x.png', content_type: 'image/png',
                                                      metadata: { 'account_id' => account.id + 1 })
      processed['carousel']['cards'][0]['header']['media_signed_id'] = alheio.signed_id

      expect(foto['cartoes'].first['midia']).to eq('tipo' => 'image', 'url' => nil)
    end

    it 'o arquivo aprovado guardado no perfil do modelo também vira endereço permanente' do
      profile = WhatsappTemplateProfile.create!(account: account, inbox: inbox, waba_id: channel.waba_id, name: 'carrossel_ofertas',
                                                language: 'pt_BR')
      profile.card_files.attach(io: StringIO.new('png'), filename: 'c1.png', content_type: 'image/png', metadata: { 'card_index' => 1 })
      processed['carousel']['cards'][1]['header'] = { 'media_stored' => true, 'media_type' => 'image' }

      expect(foto['cartoes'].last['midia']['url']).to eq(Rails.application.routes.url_helpers.rails_blob_url(profile.card_file(1).blob))
    end
  end

  describe 'teto de tamanho' do
    let(:longo) { 'Á' * 500 }
    let(:link) { "https://cdn.loja.com.br/#{'a' * 480}.jpg" }

    it 'MPM com 30 produtos no limite de cada campo cabe em 32 KB' do
      ids = Array.new(30) { |index| "#{index.to_s.rjust(2, '0')}-#{'x' * 97}" } # 100 caracteres, o máximo da Meta
      template = approved('mpm', { 'type' => 'BODY', 'text' => 'Itens' },
                          { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'MPM', 'text' => longo }] })
      Whatsapp::Templates::Enviado::Produtos.lembrar(inbox, ids.map do |id|
        Whatsapp::Templates::CatalogClient::Product.new(id: id, name: longo, price: longo, sale_price: '', image_url: link, available: true)
      end)

      foto = described_class.montar(template: template, processed: { 'products' => { 'retailer_ids' => ids + %w[a b c] } }, inbox: inbox,
                                    catalogo: :guardado)

      expect(foto['produtos'].size).to eq(30)
      expect(foto['produtos'].first.keys).to eq(%w[retailer_id nome preco foto_url])
      expect(foto['produtos'].first['nome'].length).to eq(60)
      expect(foto.to_json.bytesize).to be <= 32.kilobytes
    end

    it 'carrossel com 10 cartões no limite cabe em 32 KB' do
      card = { 'components' => [{ 'type' => 'HEADER', 'format' => 'VIDEO' }, { 'type' => 'BODY', 'text' => "#{longo} {{1}}" },
                                { 'type' => 'BUTTONS',
                                  'buttons' => Array.new(3) { { 'type' => 'URL', 'text' => longo, 'url' => "#{link}?q={{1}}" } } }] }
      template = approved('carrossel', { 'type' => 'BODY', 'text' => 'x' }, { 'type' => 'CAROUSEL', 'cards' => Array.new(12) { card } })
      cards = Array.new(12) { { 'body' => { '1' => longo }, 'buttons' => Array.new(3) { { 'type' => 'url', 'parameter' => 'a' * 20 } } } }

      foto = described_class.montar(template: template, processed: { 'carousel' => { 'cards' => cards } }, inbox: inbox)

      expect(foto['cartoes'].size).to eq(10)
      expect(foto['cartoes'].first['botoes'].size).to eq(2)
      expect(foto.to_json.bytesize).to be <= 32.kilobytes
    end
  end
end
