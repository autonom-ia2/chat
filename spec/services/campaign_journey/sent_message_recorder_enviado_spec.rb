require 'rails_helper'

# #1717: a mensagem da campanha na conversa leva a foto do que a pessoa recebeu (template_params.enviado), no envio e na
# resposta. De ponta a ponta pelo disparo real (Whatsapp::OneoffCampaignService), com a Graph falsa: o pedido à Meta não
# muda, os produtos vêm do que o disparo já leu do catálogo (uma leitura por disparo, nunca uma por pessoa) e a mídia do
# cartão é o endereço permanente do nosso armazenamento.
RSpec.describe CampaignJourney::SentMessageRecorder, :aggregate_failures do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  let(:channel) { journey_cloud_channel(account) }
  let(:inbox) { channel.inbox }
  let(:graph) { 'https://graph.facebook.com/v22.0' }
  let(:json) { { 'Content-Type' => 'application/json' } }
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }
  let(:jobs) { [SendReplyJob, EventDispatcherJob, CampaignJourney::ReplyMarkJob] }
  let!(:audience) do
    saved_audience(account: account, user: user, content: "Nome,Celular\nAna Souza,11987654321\nBia Lima,21987654321\n")
  end

  around do |example|
    with_modified_env(CAMPAIGN_JOURNEY_ENABLED: 'true') { example.run }
  ensure
    Redis::Alfred.scan_each(match: 'MESSAGE_SOURCE_KEY::*') { |key| Redis::Alfred.delete(key) }
  end

  before { allow(Rails).to receive(:cache).and_return(cache) }

  def approved(name, *components)
    { 'name' => name, 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'MARKETING', 'parameter_format' => 'POSITIONAL',
      'components' => components }
  end

  def campaign_with(template, processed)
    channel.update!(message_templates: [template])
    campaign = create(:campaign, account: account, inbox: inbox, audience: [], title: 'Ofertas', message: 'Olá',
                                 template_params: { 'name' => template['name'], 'language' => 'pt_BR', 'category' => 'MARKETING',
                                                    'processed_params' => processed })
    CampaignAudienceLink.create!(account: account, campaign: campaign, campaign_import: audience)
    campaign
  end

  def open_conversation_for(name, phone)
    contact = account.contacts.find_by!(name: name)
    contact_inbox = ContactInbox.create!(contact: contact, inbox: inbox, source_id: phone)
    create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
  end

  def send_campaign(campaign)
    perform_enqueued_jobs(only: jobs) { Whatsapp::OneoffCampaignService.new(campaign: campaign).perform }
  end

  def reply_from(phone)
    params = {
      phone_number: channel.phone_number, object: 'whatsapp_business_account',
      entry: [{ changes: [{ value: {
        contacts: [{ profile: { name: 'Bia' }, wa_id: phone }],
        messages: [{ from: phone, id: "wamid.reply-#{phone}", text: { body: 'Quero' }, timestamp: Time.current.to_i.to_s, type: 'text' }]
      } }] }]
    }.with_indifferent_access
    perform_enqueued_jobs(only: jobs) { Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: inbox, params: params).perform }
  end

  def campaign_message_in(conversation)
    conversation.messages.outgoing.sole
  end

  describe 'um produto (SPM) com cupom e link' do
    let(:template) do
      approved('produto_cupom', { 'type' => 'HEADER', 'format' => 'PRODUCT' }, { 'type' => 'BODY', 'text' => 'Olha esse!' },
               { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'SPM', 'text' => 'Ver' }] })
    end
    let(:processed) { { 'products' => { 'retailer_ids' => ['SKU1'], 'names' => { 'SKU1' => 'Tênis' } } } }

    before do
      account.enable_features!('whatsapp_campaign_products')
      catalogs = { data: [{ id: 'cat-1' }] }.to_json
      stub_request(:get, "#{graph}/#{channel.waba_id}/product_catalogs").with(query: hash_including({}))
                                                                        .to_return(status: 200, headers: json, body: catalogs)
      stub_request(:get, "#{graph}/cat-1/products").with(query: hash_including({})).to_return(
        status: 200, headers: json,
        body: { data: [{ 'retailer_id' => 'SKU1', 'name' => 'Tênis Corrida', 'price' => 'R$ 299,90',
                         'image_url' => 'https://cdn.loja.com.br/sku1.jpg', 'availability' => 'in stock', 'id' => 'm1' }] }.to_json
      )
    end

    it 'no envio, a mensagem leva nome, preço e foto que o disparo leu, numa leitura do catálogo só' do
      sent = stub_graph_messages
      conversation = open_conversation_for('Ana Souza', '5511987654321')

      send_campaign(campaign_with(template, processed))

      message = campaign_message_in(conversation)
      expect(message.additional_attributes['campaign_template_enviado']).to eq(
        'versao' => 1,
        'produto' => { 'retailer_id' => 'SKU1', 'nome' => 'Tênis Corrida', 'preco' => 'R$ 299,90', 'foto_url' => 'https://cdn.loja.com.br/sku1.jpg' },
        'botoes' => [{ 'tipo' => 'spm', 'texto' => 'Ver' }]
      )
      # Sem template_params: o envio da campanha já é contado pelo destinatário (TemplateSendCount, Health).
      expect(message.additional_attributes).to include('campaign_template_name' => 'produto_cupom')
      expect(message.additional_attributes).not_to have_key('template_params')
      expect(a_request(:get, "#{graph}/cat-1/products").with(query: hash_including({}))).to have_been_made.once
      expect(sent.size).to eq(2)
      product = { 'type' => 'product', 'product' => { 'product_retailer_id' => 'SKU1', 'catalog_id' => 'cat-1' } }
      expect(sent.first.dig('template', 'components').first).to eq('type' => 'header', 'parameters' => [product])
      expect(sent.to_json).not_to include('enviado')
    end

    it 'na resposta de quem não tinha conversa, a mensagem gravada também leva a foto' do
      stub_graph_messages
      send_campaign(campaign_with(template, processed))

      reply_from('5521987654321')

      conversation = Conversation.find_by!(inbox: inbox, contact: account.contacts.find_by!(name: 'Bia Lima'))
      enviado = campaign_message_in(conversation).additional_attributes['campaign_template_enviado']
      expect(enviado['produto']).to include('retailer_id' => 'SKU1', 'nome' => 'Tênis Corrida')
    end
  end

  describe 'carrossel de mídia com arquivo escolhido na campanha e link por pessoa' do
    let(:card) do
      { 'components' => [{ 'type' => 'HEADER', 'format' => 'IMAGE', 'example' => { 'header_handle' => ['4::aW1h'] } },
                         { 'type' => 'BODY', 'text' => 'Limão, cupom {{1}}', 'example' => { 'body_text' => [['15OFF']] } },
                         { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'URL', 'text' => 'Comprar', 'url' => 'https://loja.com.br/p/{{1}}',
                                                                'example' => ['https://loja.com.br/p/x'] }] }] }
    end
    let(:template) { approved('carrossel_ofertas', { 'type' => 'BODY', 'text' => 'Ofertas' }, { 'type' => 'CAROUSEL', 'cards' => [card, card] }) }
    let(:blob) do
      ActiveStorage::Blob.create_and_upload!(io: StringIO.new('png'), filename: 'limao.png', content_type: 'image/png',
                                             metadata: { 'account_id' => account.id })
    end
    let(:processed) do
      card_sent = { 'header' => { 'media_blob' => blob.signed_id, 'media_type' => 'image' }, 'body' => { '1' => '15OFF' },
                    'buttons' => [{ 'type' => 'url', 'parameter' => 'limao' }] }
      { 'body' => {}, 'carousel' => { 'cards' => [card_sent, card_sent] } }
    end

    it 'a mídia vai à Meta pelo id e fica gravada pelo endereço permanente' do
      stub_meta_media_upload
      sent = stub_graph_messages
      conversation = open_conversation_for('Ana Souza', '5511987654321')

      send_campaign(campaign_with(template, processed))

      cartoes = campaign_message_in(conversation).additional_attributes.dig('campaign_template_enviado', 'cartoes')
      permanente = Rails.application.routes.url_helpers.rails_blob_url(blob)
      expect(cartoes.size).to eq(2)
      expect(cartoes.first).to eq('midia' => { 'tipo' => 'image', 'url' => permanente }, 'texto' => 'Limão, cupom 15OFF',
                                  'botoes' => [{ 'tipo' => 'url', 'texto' => 'Comprar', 'url' => 'https://loja.com.br/p/limao' }])
      topo_da_meta = sent.first.dig('template', 'components').find { |c| c['type'] == 'carousel' }['cards'].first['components'].first
      expect(topo_da_meta.dig('parameters', 0, 'image')).to eq('id' => 'media_1')
      expect(sent.to_json).not_to include('media_signed_id')
    end
  end

  describe 'topo com documento guardado no perfil do modelo' do
    let(:template) do
      approved('proposta', { 'type' => 'HEADER', 'format' => 'DOCUMENT', 'example' => { 'header_handle' => ['4::cGRm'] } },
               { 'type' => 'BODY', 'text' => 'Segue a proposta.' })
    end

    def save_proposal
      profile = WhatsappTemplateProfile.create!(account: account, inbox: inbox, waba_id: channel.waba_id, name: 'proposta', language: 'pt_BR')
      profile.header_file.attach(io: StringIO.new('%PDF'), filename: 'proposta.pdf', content_type: 'application/pdf')
      profile
    end

    it 'o documento vai à Meta pelo id, com o nome, e fica gravado pelo endereço permanente' do
      profile = save_proposal
      uploads = stub_meta_media_upload
      sent = stub_graph_messages
      conversation = open_conversation_for('Ana Souza', '5511987654321')

      send_campaign(campaign_with(template, { 'header' => { 'media_url' => '', 'media_type' => 'document' }, 'body' => {} }))

      topo = campaign_message_in(conversation).additional_attributes.dig('campaign_template_enviado', 'topo')
      expect(topo).to eq('tipo' => 'document', 'url' => Rails.application.routes.url_helpers.rails_blob_url(profile.header_file.blob),
                         'nome' => 'proposta.pdf')
      expect(uploads).to eq(['proposta.pdf'])
      header = sent.first.dig('template', 'components').find { |c| c['type'] == 'header' }
      expect(header.dig('parameters', 0)).to eq('type' => 'document', 'document' => { 'id' => 'media_1', 'filename' => 'proposta.pdf' })
      expect(sent.to_json).not_to include('media_signed_id', profile.header_file.blob.signed_id)
    end

    it 'a Meta recusa a subida: o documento vai pelo link assinado, com o nome' do
      profile = save_proposal
      stub_meta_media_upload(status: 400)
      sent = stub_graph_messages
      conversation = open_conversation_for('Ana Souza', '5511987654321')

      send_campaign(campaign_with(template, { 'header' => { 'media_url' => '', 'media_type' => 'document' }, 'body' => {} }))

      topo = campaign_message_in(conversation).additional_attributes.dig('campaign_template_enviado', 'topo')
      permanente = Rails.application.routes.url_helpers.rails_blob_url(profile.header_file.blob)
      expect(topo).to eq('tipo' => 'document', 'url' => permanente, 'nome' => 'proposta.pdf')
      link_da_meta = sent.first.dig('template', 'components').find { |c| c['type'] == 'header' }
      link = link_da_meta.dig('parameters', 0, 'document')
      expect(link['link']).not_to eq(permanente)
      expect(link['filename']).to eq('proposta.pdf')
      # O link é o assinado do disco (token com validade), da chave do arquivo do perfil.
      caminho = URI.parse(link['link']).path.split('/')
      expect(caminho[1..3]).to eq(%w[rails active_storage disk])
      expect(ActiveStorage.verifier.verified(caminho[4], purpose: :blob_key)).to include(key: profile.header_file.blob.key)
      expect(sent.to_json).not_to include('media_signed_id', profile.header_file.blob.signed_id)
    end
  end
end
