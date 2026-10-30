require 'rails_helper'

# #1767: reenviar a mensagem de modelo para outra conversa = o MESMO modelo com os MESMOS valores, pelo envio de sempre.
# Formato real da Meta: os modelos de spec/fixtures/whatsapp_templates/formatos_da_conversa.json (GET /message_templates,
# como a caixa guarda) e o envio de developers.facebook.com/documentation/business-messaging/whatsapp/templates/. A prova de
# "mesmos valores" é o payload que vai à Meta: o da mensagem original e o do reenvio são iguais, só muda o destinatário.
RSpec.describe Whatsapp::Templates::ReenvioDoModelo, :aggregate_failures do
  fixture = JSON.parse(Rails.root.join('spec/fixtures/whatsapp_templates/formatos_da_conversa.json').read)
  do_fixture = ->(name) { fixture['casos'].map { |caso| caso['template'] }.find { |template| template['name'] == name } }

  let(:account) { create(:account) }
  let(:aviso) do
    { 'name' => 'aviso_pedido', 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'UTILITY',
      'components' => [{ 'type' => 'BODY', 'text' => 'Oi {{1}}, seu pedido {{2}} saiu.', 'example' => { 'body_text' => [%w[Ana 123]] } }] }
  end
  let(:com_foto) do
    { 'name' => 'novidade_com_foto', 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'MARKETING',
      'components' => [{ 'type' => 'HEADER', 'format' => 'IMAGE', 'example' => { 'header_handle' => ['https://scontent.exemplo/h.jpg'] } },
                       { 'type' => 'BODY', 'text' => 'Chegou a coleção de {{1}}.', 'example' => { 'body_text' => [['verão']] } }] }
  end
  let(:modelos) do
    [aviso, com_foto] + %w[rastreio cupom oferta_relampago carrossel_de_fotos produto_unico].map { |name| do_fixture.call(name) }
  end
  # O que a Meta responde agora na consulta do modelo (GET /message_templates?name=).
  let(:na_meta) { modelos }
  let(:origem) { canal }
  let(:canal_destino) { canal }
  let(:contato) { create(:contact, account: account, name: 'Ana Souza', phone_number: '+5511999990001') }
  let(:conversa) { conversa_em(origem, contato, '5511999990001') }
  let(:destino) { conversa_em(canal_destino, create(:contact, account: account, name: 'Chefe'), '5511999990002') }
  let(:enviados) { [] }
  let(:logs) { [] }

  def canal
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false,
                              message_templates: modelos)
  end

  def conversa_em(channel, contact, source_id)
    contact_inbox = create(:contact_inbox, contact: contact, inbox: channel.inbox, source_id: source_id)
    create(:conversation, account: account, contact: contact, contact_inbox: contact_inbox, inbox: channel.inbox)
  end

  def modelo_enviado(template, processed)
    create(:message, message_type: :outgoing, conversation: conversa, account: account, inbox: conversa.inbox, content: 'Texto do modelo',
                     additional_attributes: { template_params: { name: template['name'], language: template['language'],
                                                                 category: template['category'], processed_params: processed } })
  end

  def enviar(message)
    Whatsapp::SendOnWhatsappService.new(message: message.reload).perform
    message.reload
  end

  # #1716: o envio pela conversa relê o catálogo da WABA da caixa (o mesmo CAT-9), com o produto à venda.
  def produto_a_venda(retailer_id)
    account.enable_features!(described_class::PRODUTOS_FLAG)
    json = { 'Content-Type' => 'application/json' }
    stub_request(:get, ->(uri) { uri.path.end_with?('/product_catalogs') })
      .to_return(status: 200, headers: json, body: { data: [{ 'id' => 'CAT-9', 'name' => 'Loja' }] }.to_json)
    produto = { 'retailer_id' => retailer_id, 'name' => 'Tênis', 'price' => 'R$ 10', 'availability' => 'in stock' }
    stub_request(:get, 'https://graph.facebook.com/v22.0/CAT-9/products')
      .with(query: hash_including({}))
      .to_return(status: 200, headers: json, body: { data: [produto] }.to_json)
  end

  def reenviar(original)
    described_class.call(message_original: original, destino: destino, remetente: nil)
  end

  before do
    stub_request(:get, %r{graph\.facebook\.com/.+/message_templates}).to_return do |request|
      name = Rack::Utils.parse_query(URI(request.uri).query)['name']
      { status: 200, headers: { 'Content-Type' => 'application/json' }, body: { data: na_meta.select { |item| item['name'] == name } }.to_json }
    end
    stub_request(:post, %r{graph\.facebook\.com/.+/messages}).to_return do |request|
      enviados << JSON.parse(request.body)
      { status: 200, headers: { 'Content-Type' => 'application/json' }, body: { messages: [{ id: "wamid.#{enviados.size}" }] }.to_json }
    end
    # A foto do envio (#1717) lê o produto no catálogo para nome, preço e foto; vazio, guarda só o retailer_id.
    stub_request(:get, 'https://graph.facebook.com/v22.0/CAT-9/products')
      .with(query: hash_including({}))
      .to_return(status: 200, body: { data: [] }.to_json, headers: { 'Content-Type' => 'application/json' })
    %i[info warn error].each do |level|
      allow(Rails.logger).to receive(level).and_wrap_original do |original, *args, &block|
        logs << args.first.to_s
        original.call(*args, &block)
      end
    end
  end

  describe 'o mesmo modelo com os mesmos valores (o payload da Meta é o mesmo, só muda o destinatário)' do
    agora = Time.zone.at(fixture['agora_ms'] / 1000)
    {
      'modelo com variáveis no corpo' => ['aviso_pedido', { 'body' => { '1' => 'Ana', '2' => '123' } }],
      'botão de link com o fim variável' => ['rastreio', { 'buttons' => [{ 'type' => 'url', 'parameter' => 'AB12' }] }],
      'cupom' => ['cupom', { 'buttons' => [{ 'type' => 'copy_code', 'parameter' => 'CUPOM10' }] }],
      'oferta com validade' => ['oferta_relampago', { 'body' => { '1' => 'Ana' }, 'buttons' => [{ 'type' => 'copy_code', 'parameter' => 'HOJE25' }],
                                                      'limited_time_offer' => { 'expiration_time_ms' => 1_792_238_400_000 } }],
      'mídia no topo' => ['novidade_com_foto', { 'header' => { 'media_url' => 'https://arquivos.exemplo.com/colecao.jpg', 'media_type' => 'image' },
                                                 'body' => { '1' => 'verão' } }],
      'produto do catálogo' => ['produto_unico', { 'products' => { 'retailer_ids' => ['SKU-1'], 'catalog_id' => 'CAT-9' } }],
      'carrossel de mídia' => ['carrossel_de_fotos', { 'carousel' => { 'cards' => [
        { 'header' => { 'media_url' => 'https://arquivos.exemplo.com/1.jpg', 'media_type' => 'image' },
          'buttons' => [{ 'type' => 'quick_reply', 'payload' => 'quero-1' }] },
        { 'header' => { 'media_url' => 'https://arquivos.exemplo.com/2.jpg', 'media_type' => 'image' },
          'buttons' => [{ 'type' => 'quick_reply', 'payload' => 'quero-2' }] }
      ] } }]
    }.each do |caso, (nome, processed)|
      it caso do
        produto_a_venda('SKU-1') if nome == 'produto_unico'
        travel_to(agora) do
          original = enviar(modelo_enviado(modelos.find { |item| item['name'] == nome }, processed))
          resultado = reenviar(original)

          expect(resultado).to match(status: :criado, message: an_instance_of(Message))
          nova = enviar(resultado[:message])
          expect(nova).to have_attributes(conversation_id: destino.id, content: original.content, status: 'sent', external_error: nil)
          expect(nova.additional_attributes['template_params']).to include('name' => nome, 'language' => 'pt_BR',
                                                                           'processed_params' => processed)
          original_payload, novo_payload = enviados
          expect(novo_payload['template']).to eq(original_payload['template'])
          expect(original_payload['template']['components']).to be_present
          expect([original_payload['to'], novo_payload['to']]).to eq(%w[5511999990001 5511999990002])
        end
      end
    end
  end

  it 'conversa de outra caixa oficial da conta: confere o modelo na caixa de destino' do
    outra = canal
    destino_em_outra = conversa_em(outra, create(:contact, account: account), '5511999990003')
    original = enviar(modelo_enviado(aviso, { 'body' => { '1' => 'Ana', '2' => '123' } }))

    resultado = described_class.call(message_original: original, destino: destino_em_outra)

    expect(resultado[:status]).to eq(:criado)
    expect(resultado[:message].inbox_id).to eq(outra.inbox.id)
    expect(a_request(:get, %r{/#{outra.waba_id}/message_templates})).to have_been_made
  end

  # #1702: o encaminhamento confere fora da transação e grava dentro dela.
  it 'em duas etapas: conferir fala com a Meta e não grava; criar_conferido grava sem falar com a Meta' do
    original = enviar(modelo_enviado(aviso, { 'body' => { '1' => 'Ana', '2' => '123' } }))
    WebMock.reset_executed_requests!

    conferido = described_class.conferir(message_original: original, destino: destino)

    expect(conferido).to match(status: :conferido, reenvio: an_instance_of(described_class))
    expect(a_request(:get, %r{/message_templates})).to have_been_made
    expect(destino.messages.outgoing).to be_empty

    WebMock.reset_executed_requests!
    criado = conferido[:reenvio].criar_conferido

    expect(criado).to match(status: :criado, message: an_instance_of(Message))
    expect(criado[:message].additional_attributes['template_params']).to include('name' => aviso['name'])
    expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
  end

  it 'valor com chaves fica literal: o Liquid não roda de novo no valor do cliente' do
    original = modelo_enviado(aviso, { 'body' => { '1' => 'Ana', '2' => '123' } })
    gravado = original.additional_attributes.deep_dup
    gravado['template_params']['processed_params']['body']['2'] = '{{ contact.name }}'
    original.update_columns(additional_attributes: gravado) # rubocop:disable Rails/SkipsModelValidations

    nova = enviar(reenviar(original)[:message])

    expect(nova.additional_attributes.dig('template_params', 'processed_params', 'body', '2')).to eq('{{ contact.name }}')
    corpo = enviados.last['template']['components'].find { |component| component['type'] == 'body' }
    expect(corpo['parameters'].pluck('text')).to eq(['Ana', '{{ contact.name }}'])
  end

  describe 'arquivo nosso (link assinado com prazo): vai com link novo, nunca vencido' do
    let(:arquivo) do
      ActiveStorage::Blob.create_and_upload!(io: StringIO.new('foto'), filename: 'colecao.jpg', content_type: 'image/jpeg',
                                             metadata: { 'account_id' => account.id })
    end
    let(:link_na_nuvem) { "https://bucket.s3.sa-east-1.amazonaws.com/#{arquivo.key}?X-Amz-Expires=86400&X-Amz-Signature=velha" }

    def topo_de(message)
      message.additional_attributes.dig('template_params', 'processed_params', 'header', 'media_url')
    end

    def chave_do_disco(url)
      partes = URI.parse(url).path.split('/').reject(&:empty?)
      ActiveStorage.verifier.verified(partes[3], purpose: :blob_key).with_indifferent_access[:key]
    end

    before { stub_meta_media_upload }

    # #2367: o id gravado no envio original vale só para a caixa que subiu e vence em 30 dias; o reenvio sobe de novo.
    it 'id da mídia gravado no envio original: nunca reaproveitado, o arquivo sobe pela caixa de destino' do
      subidas = stub_meta_media_upload
      link = Whatsapp::Templates::HeaderMedia.signed_media(arquivo)['media_url']
      original = modelo_enviado(com_foto, { 'header' => { 'media_url' => link, 'media_type' => 'image', 'media_id' => 'id_antigo' },
                                            'body' => { '1' => 'verão' } })

      nova = enviar(reenviar(original)[:message])

      expect(subidas).to eq(['colecao.jpg'])
      expect(nova.additional_attributes.dig('template_params', 'processed_params', 'header', 'media_id')).to eq('media_1')
      topo = enviados.last['template']['components'].find { |component| component['type'] == 'header' }
      expect(topo.dig('parameters', 0)).to eq('type' => 'image', 'image' => { 'id' => 'media_1' })
    end

    it 'link da nuvem (S3) gravado na mensagem: o mesmo arquivo com link novo, no topo e nos cartões' do
      cartao = { 'header' => { 'media_url' => link_na_nuvem, 'media_type' => 'image' } }
      original = modelo_enviado(do_fixture.call('carrossel_de_fotos'), { 'carousel' => { 'cards' => [cartao, cartao] } })

      nova = reenviar(original)[:message]

      cards = nova.additional_attributes.dig('template_params', 'processed_params', 'carousel', 'cards')
      expect(cards.map { |card| chave_do_disco(card.dig('header', 'media_url')) }).to eq([arquivo.key, arquivo.key])
      expect(cards.map { |card| card.dig('header', 'media_url') }).not_to include(link_na_nuvem)
    end

    it 'link do disco ainda válido: assinado de novo' do
      link = Whatsapp::Templates::HeaderMedia.signed_media(arquivo)['media_url']
      original = modelo_enviado(com_foto, { 'header' => { 'media_url' => link, 'media_type' => 'image' }, 'body' => { '1' => 'verão' } })

      nova = travel_to(1.hour.from_now) { reenviar(original)[:message] }

      expect(chave_do_disco(topo_de(nova))).to eq(arquivo.key)
      expect(topo_de(nova)).not_to eq(link)
    end

    it 'arquivo nosso que sumiu: midia_indisponivel, nada criado' do
      original = modelo_enviado(com_foto, { 'header' => { 'media_url' => Whatsapp::Templates::HeaderMedia.signed_media(arquivo)['media_url'],
                                                          'media_type' => 'image' }, 'body' => { '1' => 'verão' } })
      arquivo.purge
      destino

      expect { expect(reenviar(original)).to eq(status: :falhou, motivo: 'midia_indisponivel') }.not_to change(Message, :count)
    end
  end

  describe 'mensagem de campanha (sem template_params na mensagem)' do
    let(:campanha) do
      create(:campaign, account: account, inbox: origem.inbox, audience: [], title: 'Pedidos',
                        message: 'Oi {{contact.name}}, seu pedido 123 saiu.',
                        template_params: { 'name' => 'aviso_pedido', 'language' => 'pt_BR', 'category' => 'UTILITY',
                                           'processed_params' => { 'body' => { '1' => '{{contact.name}}', '2' => '123' } } })
    end

    def mensagem_da_campanha(content, source_id: 'wamid.campanha-1', **extra)
      CampaignRecipient.create!(account: account, campaign: campanha, contact: contato, inbox: origem.inbox, source_id: source_id,
                                status: :sent, message_content: content)
      conversa.messages.create!(account: account, inbox: origem.inbox, message_type: :outgoing, content: content, source_id: source_id,
                                status: :sent, literal_content: true,
                                additional_attributes: { campaign_id: campanha.id, campaign_template_name: 'aviso_pedido' }.merge(extra))
    end

    it 'remonta os parâmetros daquela pessoa (Liquid com o contato dela) e manda o mesmo modelo' do
      resultado = reenviar(mensagem_da_campanha('Oi Ana Souza, seu pedido 123 saiu.'))

      expect(resultado[:status]).to eq(:criado)
      expect(resultado[:message].additional_attributes['template_params'])
        .to include('name' => 'aviso_pedido', 'processed_params' => { 'body' => { '1' => 'Ana Souza', '2' => '123' } })
      enviar(resultado[:message])
      corpo = enviados.last['template']['components'].find { |component| component['type'] == 'body' }
      expect(corpo['parameters'].pluck('text')).to eq(['Ana Souza', '123'])
      expect(enviados.last['to']).to eq('5511999990002')
    end

    it 'com variáveis do público: aplica os valores como o disparo' do
      campanha.update!(message: 'Oi {{1}}, seu pedido {{2}} saiu.',
                       template_params: campanha.template_params.merge('processed_params' => { 'body' => { '1' => '', '2' => '' } }))
      CampaignAudienceLink.create!(account: account, campaign: campanha,
                                   variable_bindings: { '1' => { 'source' => 'contact', 'value' => 'first_name' },
                                                        '2' => { 'source' => 'fixed', 'value' => 'PED-9' } })

      resultado = reenviar(mensagem_da_campanha('Oi Ana, seu pedido PED-9 saiu.'))

      expect(resultado[:status]).to eq(:criado)
      expect(resultado[:message].additional_attributes.dig('template_params', 'processed_params', 'body'))
        .to eq('1' => 'Ana', '2' => 'PED-9')
    end

    it 'contato mudou de nome depois do envio: vai com o nome atual, como um disparo novo (sem trava)' do
      original = mensagem_da_campanha('Oi Ana Souza, seu pedido 123 saiu.')
      contato.update!(name: 'Ana Maria')

      resultado = reenviar(original)

      expect(resultado[:status]).to eq(:criado)
      expect(resultado[:message].additional_attributes.dig('template_params', 'processed_params', 'body', '1')).to eq('Ana Maria')
    end

    it 'a campanha trocou de modelo depois do envio: vai o modelo gravado na mensagem' do
      original = mensagem_da_campanha('Oi Ana Souza, seu pedido 123 saiu.')
      campanha.update!(template_params: campanha.template_params.merge('name' => 'outro_modelo'))

      resultado = reenviar(original)

      expect(resultado[:status]).to eq(:criado)
      expect(resultado[:message].additional_attributes.dig('template_params', 'name')).to eq('aviso_pedido')
    end

    context 'when o modelo gravado na mensagem não existe mais' do
      let(:na_meta) { [] }
      let(:modelos) { [] }

      it 'falha com modelo_indisponivel' do
        expect(reenviar(mensagem_da_campanha('Oi Ana Souza, seu pedido 123 saiu.'))).to eq(status: :falhou, motivo: 'modelo_indisponivel')
      end
    end

    it 'topo com foto sem o arquivo guardado no perfil do modelo: midia_indisponivel' do
      campanha.update!(message: 'Chegou a coleção de verão.',
                       template_params: { 'name' => 'novidade_com_foto', 'language' => 'pt_BR', 'category' => 'MARKETING',
                                          'processed_params' => { 'header' => { 'media_type' => 'image' }, 'body' => { '1' => 'verão' } } })
      original = mensagem_da_campanha('Chegou a coleção de verão.')
      original.update!(additional_attributes: original.additional_attributes.merge('campaign_template_name' => 'novidade_com_foto'))

      expect(reenviar(original)).to eq(status: :falhou, motivo: 'midia_indisponivel')
    end

    it 'mensagem escrita da conversa aberta (#1335) não é modelo' do
      original = mensagem_da_campanha('Oi, tudo bem?', campaign_free_text: true)

      expect(reenviar(original)).to eq(status: :falhou, motivo: 'nao_e_modelo')
    end

    it 'sem o destinatário daquele envio: sem_parametros' do
      original = mensagem_da_campanha('Oi Ana Souza, seu pedido 123 saiu.')
      CampaignRecipient.where(source_id: original.source_id).delete_all

      expect(reenviar(original)).to eq(status: :falhou, motivo: 'sem_parametros')
    end
  end

  describe 'falha com motivo, nunca exceção, e nada é criado nem enviado' do
    let(:original) { modelo_enviado(aviso, { 'body' => { '1' => 'Ana', '2' => '123' } }) }

    def expect_falha(motivo, destino_da_vez = destino)
      original
      resultado = nil
      expect { resultado = described_class.call(message_original: original, destino: destino_da_vez) }.not_to change(Message, :count)
      expect(resultado).to eq(status: :falhou, motivo: motivo)
      expect(described_class.texto(motivo)).not_to include('translation missing')
      expect(a_request(:post, %r{/messages})).not_to have_been_made
    end

    context 'when o modelo foi pausado na Meta' do
      let(:na_meta) { [aviso.merge('status' => 'PAUSED')] }

      it { expect_falha('modelo_indisponivel') }
    end

    context 'when o modelo não existe na caixa de destino' do
      let(:na_meta) { [] }

      it { expect_falha('modelo_indisponivel') }
    end

    context 'when o modelo ganhou outra variável depois do envio' do
      let(:na_meta) do
        [aviso.merge('components' => [{ 'type' => 'BODY', 'text' => 'Oi {{1}}, pedido {{2}} em {{3}}.' }])]
      end

      it { expect_falha('modelo_mudou') }
    end

    context 'when a oferta já venceu' do
      let(:original) do
        modelo_enviado(do_fixture.call('oferta_relampago'),
                       { 'body' => { '1' => 'Ana' }, 'buttons' => [{ 'type' => 'copy_code', 'parameter' => 'HOJE25' }],
                         'limited_time_offer' => { 'expiration_time_ms' => 1_000_000 } })
      end

      it { expect_falha('oferta_vencida') }
    end

    context 'when a Meta não responde e a caixa de destino não tem lista guardada' do
      let(:canal_destino) do
        create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false,
                                  message_templates: [], message_templates_last_updated: nil)
      end

      it 'falha com erro (tentar de novo)' do
        stub_request(:get, %r{/message_templates}).to_return(status: 500)
        expect_falha('erro')
      end
    end

    it 'formato que o envio não monta: formato_nao_suportado' do
      veredito = Whatsapp::Templates::DispatchCheck::Verdict.new(reason_code: 'template_format_unsupported', source: 'template', details: {})
      conferencia = instance_double(Whatsapp::Templates::DispatchCheck, call: veredito)
      allow(Whatsapp::Templates::DispatchCheck).to receive(:new).and_return(conferencia)
      expect_falha('formato_nao_suportado')
    end

    it 'modelo de produto com a flag whatsapp_campaign_products desligada: produtos_desligados' do
      account.disable_features!(described_class::PRODUTOS_FLAG)
      original = modelo_enviado(do_fixture.call('produto_unico'), { 'products' => { 'retailer_ids' => ['SKU-1'] } })
      destino

      expect(described_class.call(message_original: original, destino: destino)).to eq(status: :falhou, motivo: 'produtos_desligados')
    end

    context 'when o modelo é de autenticação e o destinatário não tem telefone (BSUID)' do
      let(:codigo) do
        { 'name' => 'codigo_de_acesso', 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'AUTHENTICATION',
          'components' => [{ 'type' => 'BODY', 'text' => '{{1}} é o seu código.' }] }
      end
      let(:modelos) { [aviso, codigo] }
      let(:original) { modelo_enviado(codigo, { 'body' => { '1' => '123456' } }) }

      it 'falha com nao_aceito_pela_meta (regra da Meta, a mesma guarda do disparo)' do
        expect_falha('nao_aceito_pela_meta', conversa_em(canal_destino, create(:contact, account: account), 'BR.2081978709342942'))
      end
    end

    it 'caixa de destino não oficial (WhatsApp por 360dialog)' do
      nao_oficial = create(:channel_whatsapp, account: account, provider: 'default', sync_templates: false, validate_provider_config: false)
      expect_falha('caixa_nao_oficial', conversa_em(nao_oficial, create(:contact, account: account), '5511999990004'))
    end

    it 'caixa de destino que nem é WhatsApp' do
      site = create(:inbox, account: account)
      expect_falha('caixa_nao_oficial', create(:conversation, account: account, inbox: site))
    end

    it 'conversa de outra conta' do
      outra_conta = create(:account)
      outro_canal = create(:channel_whatsapp, account: outra_conta, provider: 'whatsapp_cloud', sync_templates: false,
                                              validate_provider_config: false, message_templates: modelos)
      contact_inbox = create(:contact_inbox, inbox: outro_canal.inbox, source_id: '5511999990005',
                                             contact: create(:contact, account: outra_conta))
      expect_falha('conta_diferente', create(:conversation, account: outra_conta, inbox: outro_canal.inbox, contact_inbox: contact_inbox,
                                                            contact: contact_inbox.contact))
    end

    it 'mensagem que não é modelo' do
      texto = create(:message, conversation: conversa, account: account, inbox: conversa.inbox, message_type: :outgoing, content: 'Oi')
      destino
      expect(described_class.call(message_original: texto, destino: destino)).to eq(status: :falhou, motivo: 'nao_e_modelo')
    end

    it 'erro inesperado vira motivo erro, sem levantar' do
      allow(Autonomia::LiteralMessageBuilder).to receive(:new).and_raise(ActiveRecord::RecordInvalid)

      expect_falha('erro')
      expect(logs.join).to include('erro=ActiveRecord::RecordInvalid')
    end
  end

  it 'Meta fora do ar: confere pela lista da caixa e manda' do
    stub_request(:get, %r{/message_templates}).to_return(status: 500)
    original = modelo_enviado(aviso, { 'body' => { '1' => 'Ana', '2' => '123' } })

    expect(reenviar(original)[:status]).to eq(:criado)
  end

  it 'nenhum dado do cliente no log: todas as linhas do reenvio e do envio da mensagem nova' do
    original = modelo_enviado(aviso, { 'body' => { '1' => 'Ana Secreta', '2' => 'PED-777' } })
    nao_whatsapp = create(:conversation, account: account, inbox: create(:inbox, account: account))
    destino
    logs.clear

    enviar(reenviar(original)[:message])
    described_class.call(message_original: original, destino: nao_whatsapp)

    texto = logs.join("\n")
    expect(texto).to include('[whatsapp_templates][reenvio]', 'modelo=aviso_pedido', 'criado', 'motivo=caixa_nao_oficial')
    expect(texto).not_to include('Ana Secreta', 'PED-777', 'Ana Souza', 'Chefe', '5511999990001', '5511999990002', 'Texto do modelo')
  end
end
