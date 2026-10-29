require 'rails_helper'

# #1716: a conversa manda o modelo de produto ou de carrossel com o pedido completo (os produtos escolhidos, os cartões
# com a foto); o envio completa com os construtores da campanha, pela `Whatsapp::SendOnWhatsappService` de verdade (Graph
# falsa, WebMock). Formato real da Meta: developers.facebook.com/documentation/business-messaging/whatsapp/catalogs/
# {spm,mpm,product-card-carousel}-template-messages e .../templates/marketing-templates/media-card-carousel-templates.
RSpec.describe Whatsapp::Templates::ConversationSend do
  let(:channel) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false,
                              message_templates: [one_product, many_products, product_carousel, photo_carousel])
  end
  let(:account) { channel.inbox.account }
  let(:conversation) do
    create(:conversation, inbox: channel.inbox, contact_inbox: create(:contact_inbox, inbox: channel.inbox, source_id: '5511999990000'))
  end
  let(:sent) { [] }
  let(:catalog) { [{ 'id' => 'cat-1', 'name' => 'Loja', 'product_count' => 3 }] }
  let(:stock) { { 'sku-1' => 'in stock', 'sku-2' => 'in stock' } }

  def meta_url
    "https://graph.facebook.com/v13.0/#{channel.provider_config['phone_number_id']}/messages"
  end

  def graph
    "https://graph.facebook.com/#{Whatsapp::Templates::MetaClient.api_version}"
  end

  def products_url
    "#{graph}/cat-1/products"
  end

  def json
    { 'Content-Type' => 'application/json' }
  end

  def body
    { 'type' => 'BODY', 'text' => 'Oi {{1}}' }
  end

  def approved(name, *components)
    { 'name' => name, 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'MARKETING',
      'parameter_format' => 'POSITIONAL', 'components' => components }
  end

  def one_product
    approved('produto_unico', { 'type' => 'HEADER', 'format' => 'PRODUCT' }, body,
             { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'SPM', 'text' => 'Ver' }] })
  end

  def many_products
    approved('lista_de_produtos', body, { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'MPM', 'text' => 'Ver itens' }] })
  end

  def product_carousel
    card = { 'components' => [{ 'type' => 'HEADER', 'format' => 'PRODUCT' },
                              { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'SPM', 'text' => 'Ver' }] }] }
    approved('carrossel_de_produtos', body, { 'type' => 'CAROUSEL', 'cards' => [card, card] })
  end

  def photo_carousel
    card = { 'components' => [{ 'type' => 'HEADER', 'format' => 'IMAGE' }, { 'type' => 'BODY', 'text' => 'Leve {{1}}' }] }
    approved('vitrine_de_fotos', body, { 'type' => 'CAROUSEL', 'cards' => [card, card] })
  end

  def products_with(ids)
    { 'body' => { '1' => 'Ana' }, 'products' => { 'retailer_ids' => ids, 'names' => { 'sku-1' => 'Tênis', 'sku-2' => 'Mochila' } } }
  end

  def photo(account_id = account.id, upload: false)
    metadata = { 'account_id' => account_id }
    metadata['conversation_upload'] = true if upload
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new('png'), filename: 'foto.png', content_type: 'image/png', metadata: metadata)
  end

  def photo_cards(blobs, texts = %w[tênis mochila])
    cards = blobs.zip(texts).map { |blob, text| { 'header' => { 'media_blob' => blob.signed_id }, 'body' => { '1' => text } } }
    { 'body' => { '1' => 'Ana' }, 'carousel' => { 'cards' => cards } }
  end

  def send_message(template, processed)
    message = create(:message, message_type: :outgoing, conversation: conversation, account: conversation.account, inbox: channel.inbox,
                               additional_attributes: { template_params: { name: template['name'], language: 'pt_BR',
                                                                           category: 'MARKETING', processed_params: processed } })
    Whatsapp::SendOnWhatsappService.new(message: message).perform
    message.reload
  end

  def error_text(key, **args)
    I18n.t("whatsapp_templates.errors.#{key}", **args)
  end

  before do
    account.enable_features!('whatsapp_campaign_products')
    stub_request(:post, meta_url).to_return do |request|
      sent << JSON.parse(request.body).dig('template', 'components')
      { status: 200, body: { messages: [{ id: 'wamid.1' }] }.to_json, headers: json }
    end
    catalogs = stub_request(:get, "#{graph}/#{channel.waba_id}/product_catalogs").with(query: hash_including({}))
    catalogs.to_return { { status: 200, headers: json, body: { data: catalog }.to_json } }
    stub_request(:get, products_url).with(query: hash_including({})).to_return do
      rows = stock.map { |id, availability| { 'retailer_id' => id, 'name' => id, 'price' => 'R$ 10', 'availability' => availability } }
      { status: 200, headers: json, body: { data: rows }.to_json }
    end
  end

  it 'one product: the catalog of the inbox WABA goes in the header, never from the screen' do
    message = send_message(one_product, products_with(['sku-1']).deep_merge('products' => { 'catalog_id' => 'outro' }))

    expect(message).to have_attributes(source_id: 'wamid.1', external_error: nil)
    expect(sent.last.first).to eq(
      'type' => 'header',
      'parameters' => [{ 'type' => 'product', 'product' => { 'product_retailer_id' => 'sku-1', 'catalog_id' => 'cat-1' } }]
    )
    # A mensagem guarda o pedido como a tela mandou; o catálogo da WABA vale só para este envio.
    expect(message.additional_attributes.dig('template_params', 'processed_params', 'products', 'catalog_id')).to eq('outro')
    expect(message.additional_attributes.dig('template_params', 'enviado', 'produto', 'retailer_id')).to eq('sku-1')
  end

  it 'many products (MPM): the list in the chosen order, the first as the thumbnail' do
    send_message(many_products, products_with(%w[sku-2 sku-1]))

    action = sent.last.last.dig('parameters', 0, 'action')
    expect(sent.last.last).to include('sub_type' => 'mpm', 'index' => 0)
    expect(action['thumbnail_product_retailer_id']).to eq('sku-2')
    expect(action.dig('sections', 0, 'product_items')).to eq([{ 'product_retailer_id' => 'sku-2' }, { 'product_retailer_id' => 'sku-1' }])
  end

  it 'product carousel: one card per product, with the catalog' do
    send_message(product_carousel, products_with(%w[sku-1 sku-2]))

    cards = sent.last.find { |component| component['type'] == 'carousel' }['cards']
    expect(cards.map { |card| [card['card_index'], card.dig('components', 0, 'parameters', 0, 'product', 'product_retailer_id')] })
      .to eq([[0, 'sku-1'], [1, 'sku-2']])
    expect(cards.map { |card| card.dig('components', 0, 'parameters', 0, 'product', 'catalog_id') }).to eq(%w[cat-1 cat-1])
  end

  it 'a product that sold out after it was chosen is not sent, with its name' do
    stock['sku-2'] = 'out of stock'
    message = send_message(many_products, products_with(%w[sku-1 sku-2]))

    expect(message).to have_attributes(status: 'failed', external_error: error_text('conversation_product_unavailable', products: 'Mochila'))
    expect(a_request(:post, meta_url)).not_to have_been_made
  end

  it 'without a catalog connected to the WABA nothing is sent' do
    catalog.clear
    message = send_message(one_product, products_with(['sku-1']))

    expect(message.external_error).to eq(error_text('conversation_catalog_missing'))
    expect(a_request(:post, meta_url)).not_to have_been_made
  end

  it 'Meta out of reach while reading the catalog: not sent, try again later' do
    stub_request(:get, products_url).with(query: hash_including({})).to_return(status: 503, headers: json, body: '{}')
    allow_any_instance_of(Whatsapp::Templates::CatalogClient).to receive(:sleep) # rubocop:disable RSpec/AnyInstance
    message = send_message(one_product, products_with(['sku-1']))

    expect(message.external_error).to eq(error_text('conversation_catalog_unreachable'))
    expect(a_request(:post, meta_url)).not_to have_been_made
  end

  it 'products only with the whatsapp_campaign_products flag, as in the campaign' do
    account.disable_features!('whatsapp_campaign_products')
    message = send_message(one_product, products_with(['sku-1']))

    expect(message.external_error).to eq(error_text('conversation_products_disabled'))
    expect(a_request(:post, meta_url)).not_to have_been_made
  end

  it 'too many products for the template are refused before the catalog' do
    message = send_message(product_carousel, products_with(Array.new(11) { |index| "sku-#{index}" }))

    expect(message.external_error).to eq(error_text('conversation_products'))
    expect(a_request(:get, products_url).with(query: hash_including({}))).not_to have_been_made
  end

  # #2367: pelo link, a Meta baixa a foto do nosso armazenamento e a busca falha com 131053; pelo id, não baixa.
  it 'photo carousel: each chosen photo goes up to Meta and the card carries its id, the message keeps the file reference' do
    uploads = stub_meta_media_upload
    blobs = [photo, photo]
    message = send_message(photo_carousel, photo_cards(blobs))

    cards = sent.last.find { |component| component['type'] == 'carousel' }['cards']
    expect(uploads).to eq(%w[foto.png foto.png])
    expect(cards.map { |card| card.dig('components', 0, 'parameters', 0, 'image') }).to eq([{ 'id' => 'media_1' }, { 'id' => 'media_2' }])
    expect(cards.map { |card| card.dig('components', 1, 'parameters', 0, 'text') }).to eq(%w[tênis mochila])
    expect(sent.last.to_json).not_to include(blobs.first.signed_id)
    stored = message.additional_attributes.dig('template_params', 'processed_params', 'carousel', 'cards')
    expect(stored.map { |card| card.dig('header', 'media_blob') }).to eq(blobs.map(&:signed_id))
    expect(message.additional_attributes.dig('template_params', 'enviado', 'cartoes').size).to eq(2)
  end

  it 'photo carousel: Meta refuses the upload and each card goes as a signed link' do
    stub_meta_media_upload(status: 400)
    message = send_message(photo_carousel, photo_cards([photo, photo]))

    cards = sent.last.find { |component| component['type'] == 'carousel' }['cards']
    expect(message.external_error).to be_nil
    expect(cards.map { |card| card.dig('components', 0, 'parameters', 0, 'image', 'link') }).to all(start_with('http'))
  end

  it 'a computer photo used in a send stops being temporary (the conversation shows it)' do
    stub_meta_media_upload
    uploaded = photo(upload: true)
    send_message(photo_carousel, photo_cards([uploaded, photo]))

    expect(uploaded.reload.metadata).to include('conversation_upload' => true, 'conversation_sent' => true)
  end

  it 'a photo from another account is refused without calling Meta' do
    message = send_message(photo_carousel, photo_cards([photo, photo(account.id + 1)]))

    expect(message.external_error).to eq(error_text('conversation_carousel'))
    expect(a_request(:post, meta_url)).not_to have_been_made
  end

  it 'a card without its text is still refused (incomplete send)' do
    message = send_message(photo_carousel, photo_cards([photo, photo], ['tênis', '']))

    expect(message.external_error).to eq(error_text('conversation_carousel'))
    expect(a_request(:post, meta_url)).not_to have_been_made
  end
end
