require 'rails_helper'

# #1334: a campanha do WhatsApp oficial envia os formatos novos — cupom (copiar código), oferta por tempo limitado com
# validade, carrossel com a mídia de cada cartão, formulário (Flow) com flow_token e botão de catálogo — com o que a
# Meta exige no envio. Código de verificação continua fora (é pedido por uma pessoa num app, nunca para uma lista).
RSpec.describe Whatsapp::Templates::SendParams, :aggregate_failures do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  let(:channel) { journey_cloud_channel(account) }
  let(:inbox) { channel.inbox }
  let(:audience) do
    saved_audience(account: account, user: user, content: "Nome,Celular\nAna Souza,11987654321\nBia Lima,21987654321\n")
  end
  let(:ahead) { 3.days.from_now.to_i * 1000 }

  let(:body) { { 'type' => 'BODY', 'text' => 'Chegou a oferta do mês.' } }
  let(:offer) do
    approved('oferta', { 'type' => 'HEADER', 'format' => 'IMAGE' },
             { 'type' => 'LIMITED_TIME_OFFER', 'limited_time_offer' => { 'text' => 'Só hoje', 'has_expiration' => true } }, body,
             { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'COPY_CODE', 'example' => 'CUPOM10' },
                                                  { 'type' => 'URL', 'text' => 'Comprar', 'url' => 'https://loja.com' }] })
  end
  let(:card) do
    { 'components' => [{ 'type' => 'HEADER', 'format' => 'IMAGE' }, { 'type' => 'BODY', 'text' => 'Produto' },
                       { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'URL', 'text' => 'Ver', 'url' => 'https://loja.com' }] }] }
  end
  let(:carousel) { approved('vitrine', body, { 'type' => 'CAROUSEL', 'cards' => [card, card] }) }
  let(:flow_and_catalog) do
    approved('loja', body, { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'CATALOG', 'text' => 'Ver catálogo' },
                                                                { 'type' => 'FLOW', 'text' => 'Pedir', 'flow_id' => '9' }] })
  end

  # #1418: carrossel de produtos do catálogo (aprovado com 2 cartões, manda de 2 a 10).
  def product_carousel
    card = { 'components' => [{ 'type' => 'HEADER', 'format' => 'PRODUCT' }, { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'SPM' }] }] }
    approved('cartoes_de_produtos', body, { 'type' => 'CAROUSEL', 'cards' => [card, card] })
  end

  def approved(name, *components)
    { 'name' => name, 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'MARKETING', 'components' => components }
  end

  # O arquivo que a pessoa escolheu na campanha sobe pelo upload de mídia dos Modelos (blob com a conta).
  def uploaded(name, account_id: account.id, content_type: 'image/png', size: 3)
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new('x' * size), filename: name, content_type: content_type,
                                           identify: false, metadata: { 'account_id' => account_id })
  end

  def stored_cards
    { 'carousel' => { 'cards' => [{ 'header' => { 'media_stored' => true, 'media_type' => 'image' } }] * 2 } }
  end

  before do
    channel.update_columns(message_templates: [offer, carousel, flow_and_catalog, product_carousel]) # rubocop:disable Rails/SkipsModelValidations
  end

  def params(name, processed)
    { 'name' => name, 'language' => 'pt_BR', 'category' => 'MARKETING', 'processed_params' => processed }
  end

  def offer_params(code: 'CUPOM10', expiration: ahead)
    params('oferta', { 'header' => { 'media_url' => 'https://loja.com/oferta.png', 'media_type' => 'image' },
                       'limited_time_offer' => { 'expiration_time_ms' => expiration },
                       'buttons' => [{ 'type' => 'copy_code', 'parameter' => code }] })
  end

  def create_campaign(template_params)
    CampaignJourney::WhatsappCampaignCreator.new(
      account: account, campaign_import: audience, channel: 'whatsapp_cloud',
      attributes: { title: 'Formatos', inbox_id: inbox.id, template_params: template_params, variable_bindings: {} }
    ).perform
  end

  def refusal_code(template_params)
    create_campaign(template_params)
    nil
  rescue CampaignJourney::WhatsappCampaignCreator::Error => e
    e.code
  end

  def save_card_files(name = 'vitrine')
    profile = WhatsappTemplateProfile.create!(account: account, inbox: inbox, waba_id: channel.waba_id, name: name, language: 'pt_BR')
    2.times do |index|
      profile.card_files.attach(io: StringIO.new('png'), filename: "cartao-#{index + 1}.png", content_type: 'image/png',
                                metadata: { 'card_index' => index })
    end
    profile
  end

  def component(body, type)
    Array(body.dig('template', 'components')).find { |item| item['type'] == type }
  end

  describe 'criação da campanha' do
    it 'oferta: aceita validade à frente e cupom; recusa sem validade, validade passada e cupom vazio ou longo' do
      expect(create_campaign(offer_params).template_params.dig('processed_params', 'limited_time_offer'))
        .to eq('expiration_time_ms' => ahead)
      expect(refusal_code(offer_params(expiration: nil))).to eq('offer_expiration_required')
      expect(refusal_code(offer_params(expiration: 'amanhã'))).to eq('offer_expiration_required')
      expect(refusal_code(offer_params(expiration: 1.hour.ago.to_i * 1000))).to eq('offer_expiration_past')
      expect(refusal_code(offer_params(code: ' '))).to eq('coupon_code_invalid')
      expect(refusal_code(offer_params(code: 'A' * 16))).to eq('coupon_code_invalid')
    end

    it 'carrossel: sem link usa o arquivo de cada cartão guardado no modelo; sem arquivo nem link, recusa' do
      expect(refusal_code(params('vitrine', { 'carousel' => { 'cards' => [{}, {}] } }))).to eq('carousel_media_required')

      save_card_files
      campaign = create_campaign(params('vitrine', { 'carousel' => { 'cards' => [{}, {}] } }))

      expect(campaign.template_params.dig('processed_params', 'carousel', 'cards').pluck('header'))
        .to eq([{ 'media_stored' => true, 'media_type' => 'image' }] * 2)
    end

    it 'carrossel: arquivo escolhido na campanha vale quando é da conta, do tipo do cartão e do tamanho que a Meta aceita' do
      own = uploaded('nova.png')
      cards = [{ 'header' => { 'media_blob' => own.signed_id } }, { 'header' => { 'media_blob' => uploaded('outra.png').signed_id } }]

      header = create_campaign(params('vitrine', { 'carousel' => { 'cards' => cards } }))
               .template_params.dig('processed_params', 'carousel', 'cards', 0, 'header')
      expect(header).to eq('media_blob' => own.signed_id, 'media_type' => 'image')

      [uploaded('alheia.png', account_id: account.id + 1), uploaded('filme.mp4', content_type: 'video/mp4'),
       uploaded('grande.png', size: 5.megabytes + 1)].each do |blob|
        bad = [{ 'header' => { 'media_blob' => blob.signed_id } }, cards.last]
        expect(refusal_code(params('vitrine', { 'carousel' => { 'cards' => bad } }))).to eq('carousel_media_invalid')
      end
      expect(refusal_code(params('vitrine', { 'carousel' => { 'cards' => [{ 'header' => { 'media_blob' => 'x' } }, cards.last] } })))
        .to eq('carousel_media_invalid')
    end

    it 'carrossel: link digitado precisa ser http(s) e há um item por cartão do modelo' do
      linked = { 'header' => { 'media_url' => 'https://loja.com/1.png' } }

      expect(refusal_code(params('vitrine', { 'carousel' => { 'cards' => [linked] } }))).to eq('carousel_cards_mismatch')
      expect(refusal_code(params('vitrine', { 'carousel' => { 'cards' => [linked, { 'header' => { 'media_url' => 'ftp://x/2.png' } }] } })))
        .to eq('carousel_media_invalid')
      expect(create_campaign(params('vitrine', { 'carousel' => { 'cards' => [linked, linked] } }))
               .template_params.dig('processed_params', 'carousel', 'cards', 0, 'header'))
        .to eq('media_url' => 'https://loja.com/1.png', 'media_type' => 'image')
    end

    it 'catálogo: marca o botão sozinho, sem nada a preencher na tela; o botão sem nada a enviar guarda a posição' do
      campaign = create_campaign(params('loja', {}))

      expect(campaign.template_params.dig('processed_params', 'buttons')).to eq([{ 'type' => 'catalog' }, { 'type' => 'static' }])
    end

    it 'carrossel: campo no texto do cartão ou no fim do link do botão precisa do valor' do
      card['components'].last['buttons'] = [{ 'type' => 'URL', 'text' => 'Ver', 'url' => 'https://loja.com/{{1}}' }]
      channel.update_columns(message_templates: [carousel]) # rubocop:disable Rails/SkipsModelValidations
      linked = { 'header' => { 'media_url' => 'https://loja.com/1.png' } }

      expect(refusal_code(params('vitrine', { 'carousel' => { 'cards' => [linked, linked] } }))).to eq('carousel_button_required')
      card['components'][1]['text'] = 'Tênis {{1}}'
      channel.update_columns(message_templates: [carousel]) # rubocop:disable Rails/SkipsModelValidations
      buttoned = linked.merge('buttons' => [{ 'type' => 'url', 'parameter' => 'tenis' }])
      expect(refusal_code(params('vitrine', { 'carousel' => { 'cards' => [buttoned, buttoned] } }))).to eq('carousel_body_required')
      with_value = buttoned.merge('body' => { '1' => 'azul' })
      expect(create_campaign(params('vitrine', { 'carousel' => { 'cards' => [with_value, with_value] } }))).to be_persisted
    end

    it 'chave que o modelo não tem não fica guardada (validade sem contagem, carrossel num modelo comum)' do
      offer['components'][1]['limited_time_offer']['has_expiration'] = false
      channel.update_columns(message_templates: [offer]) # rubocop:disable Rails/SkipsModelValidations

      processed = create_campaign(offer_params.deep_merge('processed_params' => { 'carousel' => { 'cards' => [{}] } }))
                  .template_params['processed_params']

      expect(processed.keys).not_to include('limited_time_offer', 'carousel')
    end

    it 'pedido malformado vira recusa com código, não erro 500' do
      expect(refusal_code(params('vitrine', { 'carousel' => 'cartões' }))).to eq('carousel_cards_mismatch')
      header = { 'media_url' => 'https://loja.com/oferta.png', 'media_type' => 'image' }
      expect(refusal_code(params('oferta', { 'header' => header, 'limited_time_offer' => 'amanhã', 'buttons' => 'CUPOM' })))
        .to eq('coupon_code_invalid')
    end
  end

  describe 'produtos do catálogo (#1418)' do
    def chosen
      names = { 'camiseta' => 'Camiseta', 'tenis' => 'Tênis', 'fone' => 'Fone' }
      { 'products' => { 'retailer_ids' => names.keys, 'names' => names } }
    end

    def graph
      'https://graph.facebook.com/v22.0'
    end

    def graph_answer(body)
      { status: 200, headers: { 'Content-Type' => 'application/json' }, body: body.to_json }
    end

    def stub_catalog(available: %w[camiseta tenis fone])
      stub_request(:get, "#{graph}/#{channel.waba_id}/product_catalogs")
        .with(query: hash_including({})).to_return(graph_answer(data: [{ id: 'cat-1', name: 'Loja', product_count: 3 }]))
      rows = %w[camiseta tenis fone].map do |id|
        { retailer_id: id, name: id, price: 'R$1', image_url: '', availability: available.include?(id) ? 'in stock' : 'out of stock' }
      end
      stub_request(:get, "#{graph}/cat-1/products").with(query: hash_including({})).to_return(graph_answer(data: rows))
    end

    # A campanha nasce com a flag ligada (a criação exige); `flag: false` simula desligá-la antes do disparo.
    def dispatch_products(processed, flag: true)
      flag ? account.enable_features!('whatsapp_campaign_products') : account.disable_features!('whatsapp_campaign_products')
      campaign = create(:campaign, account: account, inbox: inbox, audience: [], message: 'Chegou a oferta do mês.',
                                   template_params: params('cartoes_de_produtos', processed))
      CampaignAudienceLink.create!(account: account, campaign: campaign, campaign_import: audience, variable_bindings: {}, variable_defaults: {})
      Whatsapp::OneoffCampaignService.new(campaign: campaign).perform
      campaign
    end

    it 'criação: só com a flag da conta e com 2 a 10 produtos; guarda os códigos e os nomes, nunca o catálogo da tela' do
      expect(refusal_code(params('cartoes_de_produtos', chosen))).to eq('products_disabled')

      account.enable_features!('whatsapp_campaign_products')
      expect(refusal_code(params('cartoes_de_produtos', {}))).to eq('products_required')
      expect(refusal_code(params('cartoes_de_produtos', { 'products' => { 'retailer_ids' => ['so-um'] } }))).to eq('products_count')

      campaign = create_campaign(params('cartoes_de_produtos', chosen.deep_merge('products' => { 'catalog_id' => 'da-tela' })))
      expect(campaign.template_params.dig('processed_params', 'products')).to eq(chosen['products'])
    end

    it 'disparo: cada envio leva um cartão por produto, com o catálogo da WABA da caixa' do
      stub_catalog
      sent = stub_graph_messages

      campaign = dispatch_products(chosen)

      expect(CampaignPause.open_for(campaign)).to be_nil
      expect(sent.size).to eq(2)
      cards = component(sent.first, 'carousel')['cards']
      expect(cards.map { |card| card.dig('components', 0, 'parameters', 0, 'product') })
        .to eq(%w[camiseta tenis fone].map { |id| { 'product_retailer_id' => id, 'catalog_id' => 'cat-1' } })
    end

    it 'disparo: produto esgotado para a campanha inteira, com o nome dele, e ninguém recebe' do
      stub_catalog(available: %w[camiseta fone])
      sent = stub_graph_messages

      campaign = dispatch_products(chosen)

      expect(sent).to be_empty
      pause = CampaignPause.open_for(campaign)
      expect(pause.reason_code).to eq('template_product_unavailable')
      expect(pause.source).to eq('template')
      expect(pause.details).to include('product_ids' => ['tenis'], 'product_names' => ['Tênis'])
    end

    it 'disparo: flag desligada depois da criação para a campanha inteira com motivo próprio, sem ler o catálogo' do
      stub_catalog
      sent = stub_graph_messages

      campaign = dispatch_products(chosen, flag: false)

      expect(sent).to be_empty
      pause = CampaignPause.open_for(campaign)
      expect(pause.reason_code).to eq('template_products_disabled')
      expect(pause.source).to eq('template')
      expect(a_request(:get, ->(uri) { uri.path.end_with?('/product_catalogs') })).not_to have_been_made
    end
  end

  describe 'disparo' do
    def dispatch(template_params)
      campaign = create(:campaign, account: account, inbox: inbox, audience: [], message: 'Chegou a oferta do mês.',
                                   template_params: template_params)
      CampaignAudienceLink.create!(account: account, campaign: campaign, campaign_import: audience, variable_bindings: {}, variable_defaults: {})
      Whatsapp::OneoffCampaignService.new(campaign: campaign).perform
      campaign
    end

    it 'oferta: cada envio leva a validade e o cupom' do
      sent = stub_graph_messages

      dispatch(offer_params)

      expect(sent.size).to eq(2)
      expect(component(sent.first, 'limited_time_offer')['parameters'])
        .to eq([{ 'type' => 'limited_time_offer', 'limited_time_offer' => { 'expiration_time_ms' => ahead } }])
      expect(component(sent.first, 'button'))
        .to include('sub_type' => 'copy_code', 'parameters' => [{ 'type' => 'coupon_code', 'coupon_code' => 'CUPOM10' }])
    end

    it 'oferta vencida enquanto esperava: ninguém recebe e a campanha para com o motivo' do
      sent = stub_graph_messages

      campaign = dispatch(offer_params(expiration: 1.hour.ago.to_i * 1000))

      expect(sent).to be_empty
      expect(CampaignPause.open_for(campaign)).to have_attributes(source: 'template', reason_code: 'template_offer_expired')
    end

    # #2367: cada arquivo sobe à Meta uma vez no disparo e o cartão leva o id (pelo link, a busca da Meta falha com 131053).
    it 'carrossel: o arquivo guardado de cada cartão sobe à Meta e o cartão leva o id' do
      save_card_files
      uploads = stub_meta_media_upload
      sent = stub_graph_messages

      dispatch(params('vitrine', stored_cards))

      cards = component(sent.first, 'carousel')['cards']
      expect(cards.pluck('card_index')).to eq([0, 1])
      expect(uploads).to eq(%w[cartao-1.png cartao-2.png])
      expect(cards.map { |item| item.dig('components', 0, 'parameters', 0, 'image') }).to eq([{ 'id' => 'media_1' }, { 'id' => 'media_2' }])
    end

    it 'carrossel: o arquivo escolhido na campanha sobe à Meta e o cartão leva o id' do
      uploads = stub_meta_media_upload
      sent = stub_graph_messages
      cards = %w[nova.png outra.png].map { |name| { 'header' => { 'media_blob' => uploaded(name).signed_id, 'media_type' => 'image' } } }

      dispatch(params('vitrine', { 'carousel' => { 'cards' => cards } }))

      images = component(sent.first, 'carousel')['cards'].map { |item| item.dig('components', 0, 'parameters', 0, 'image') }
      expect(uploads).to eq(%w[nova.png outra.png])
      expect(images).to eq([{ 'id' => 'media_1' }, { 'id' => 'media_2' }])
    end

    it 'carrossel: a Meta recusa a subida e o cartão leva o link gerado no disparo' do
      stub_meta_media_upload(status: 400)
      sent = stub_graph_messages
      cards = %w[nova.png outra.png].map { |name| { 'header' => { 'media_blob' => uploaded(name).signed_id, 'media_type' => 'image' } } }

      dispatch(params('vitrine', { 'carousel' => { 'cards' => cards } }))

      links = component(sent.first, 'carousel')['cards'].map { |item| item.dig('components', 0, 'parameters', 0, 'image', 'link') }
      expect(links).to match([include('nova.png'), include('outra.png')])
    end

    it 'carrossel sem os arquivos do modelo na hora do disparo: para com template_media_missing' do
      sent = stub_graph_messages

      campaign = dispatch(params('vitrine', stored_cards))

      expect(sent).to be_empty
      expect(CampaignPause.open_for(campaign).reason_code).to eq('template_media_missing')
    end

    it 'formulário e catálogo: o botão do Flow leva o flow_token da campanha e o do catálogo vai sem parâmetro' do
      sent = stub_graph_messages

      campaign = dispatch(params('loja', { 'buttons' => [{ 'type' => 'catalog' }] }))

      buttons = sent.first.dig('template', 'components').select { |item| item['type'] == 'button' }
      expect(sent.size).to eq(2)
      expect(buttons).to eq([{ 'type' => 'button', 'sub_type' => 'catalog', 'index' => 0 },
                             { 'type' => 'button', 'sub_type' => 'flow', 'index' => 1,
                               'parameters' => [{ 'type' => 'action', 'action' => { 'flow_token' => "chat2you_campaign_#{campaign.id}" } }] }])
    end

    it 'campanha antiga com valores em lista (formato legado) segue enviando como antes, sem extras' do
      form = approved('formulario', { 'type' => 'BODY', 'text' => 'Oi {{1}}' },
                      { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'FLOW', 'text' => 'Pedir' }] })
      channel.update_columns(message_templates: [form]) # rubocop:disable Rails/SkipsModelValidations
      sent = stub_graph_messages

      campaign = dispatch(params('formulario', ['Ana']))

      expect(CampaignPause.open_for(campaign)).to be_nil
      expect(sent.size).to eq(2)
      expect(sent.first.dig('template', 'components').pluck('type')).to eq(['body'])
    end

    # #1405 (Multifunil): o robô toma a conversa em toda resposta pública, menos na mensagem de campanha. A mensagem dos
    # formatos novos gravada na conversa precisa continuar sendo de campanha.
    it 'a mensagem gravada na conversa é de campanha (campaign_message?)' do
      sent = stub_graph_messages
      ana = audience.campaign_import_rows.order(:row_number).first.contact
      contact_inbox = ContactInbox.create!(contact: ana, inbox: inbox, source_id: '5511987654321')
      conversation = create(:conversation, account: account, inbox: inbox, contact: ana, contact_inbox: contact_inbox)

      campaign = dispatch(offer_params)

      expect(sent.size).to eq(2)
      message = conversation.messages.outgoing.sole
      expect(message.additional_attributes).to include('campaign_id' => campaign.id)
      expect(message.send(:campaign_message?)).to be(true) # privado no Message; é o que o #1405 consulta
    end
  end
end
