require 'rails_helper'

# API de Modelos do WhatsApp oficial (#1330) como administrador, com a Graph falsa: lista (sync + perfil, sem perfil cai no
# nome técnico), cria, edita, apaga, duplica, sobe mídia, "onde está em uso", modelos do sistema protegidos e o
# isolamento entre contas que dividem o mesmo token.
RSpec.describe 'Api::V1::Accounts::Inboxes::WhatsappTemplates', type: :request do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false,
                              message_templates: templates)
  end
  let(:inbox) { channel.inbox }
  let(:base) { "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/whatsapp_templates" }
  let(:graph) { 'https://graph.facebook.com/v22.0' }
  let(:templates_url) { "#{graph}/#{channel.waba_id}/message_templates" }
  let(:json) { { 'Content-Type' => 'application/json' } }
  let(:mine) do
    { 'id' => '11', 'name' => 'pedido_enviado', 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'UTILITY',
      'components' => [{ 'type' => 'BODY', 'text' => 'Olá {{1}}, seu pedido saiu.' }] }
  end
  let(:booking) do
    { 'id' => '12', 'name' => 'agendamento_ao_marcar_v1', 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'UTILITY',
      'components' => [{ 'type' => 'BODY', 'text' => 'Olá {{1}}! {{2}} acesse {{3}} e escolha.' }] }
  end
  let(:csat) { { 'id' => '13', 'name' => "customer_satisfaction_survey_#{inbox.id}", 'language' => 'pt_BR', 'status' => 'APPROVED' } }
  let(:templates) { [] }

  before do
    channel.update_columns(message_templates: [mine, booking, csat]) # rubocop:disable Rails/SkipsModelValidations
    account.enable_features!('whatsapp_templates_journey')
    allow_any_instance_of(Whatsapp::Templates::MetaClient).to receive(:sleep) # rubocop:disable RSpec/AnyInstance
  end

  def call(verb, path, params = {}, user: admin)
    public_send(verb, path, params: params, headers: user.create_new_auth_token, as: :json)
  end

  def stub_lookup(name, data)
    stub_request(:get, templates_url).with(query: hash_including('name' => name))
                                     .to_return(status: 200, headers: json, body: { data: data }.to_json)
  end

  # Sem a flag `whatsapp_templates_journey`, nenhuma escrita chega à Meta (apagar lá não tem volta).
  describe 'sem a flag da conta' do
    before { account.disable_features!('whatsapp_templates_journey') }

    it 'cada escrita responde 404 sem nenhuma chamada à Meta' do
      file = Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/avatar.png'), 'image/png')
      writes = [[:post, base, { template: { name: 'novo', language: 'pt_BR' } }],
                [:patch, "#{base}/11", { template: { category: 'UTILITY' } }],
                [:delete, "#{base}/11", {}]]

      writes.each do |verb, path, params|
        call(verb, path, params)
        expect(response).to have_http_status(:not_found), "#{verb} #{path} devolveu #{response.status}"
        expect(response.parsed_body['error']).to eq('feature_disabled')
      end
      post "#{base}/media", params: { file: file }, headers: admin.create_new_auth_token
      expect(response).to have_http_status(:not_found)

      expect(a_request(:any, graph_host)).not_to have_been_made
      expect(channel.reload.message_templates.pluck('id')).to eq(%w[11 12 13])
    end

    it 'listar e "onde está em uso" seguem abertos' do
      call(:get, base)
      expect(response).to have_http_status(:ok)

      call(:get, "#{base}/11/usage")
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'GET index' do
    # Produção (12/10/2026): caixas com message_templates = {} (objeto vazio, o padrão do sync vazio), não [].
    it 'trata a lista guardada como objeto vazio ({}) como nenhum modelo, sem erro' do
      channel.update_columns(message_templates: {}) # rubocop:disable Rails/SkipsModelValidations
      manager = Whatsapp::Templates::Manager.new(inbox: inbox.reload, user: admin, account_user: admin.account_users.first,
                                                 visible_cards: Crm::Card.none)

      call(:get, base)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['payload']).to eq([])
      expect(manager.list).to eq([])
      expect { manager.usage('11') }.to raise_error(Whatsapp::Templates::MetaClient::NotFound)
    end

    it 'lista a lista sincronizada com o perfil; sem perfil, o nome amigável é o nome técnico' do
      WhatsappTemplateProfile.create!(account: account, inbox: inbox, waba_id: channel.waba_id, name: 'pedido_enviado',
                                      language: 'pt_BR', friendly_name: 'Pedido enviado', fields: { '1' => 'cliente.primeiro_nome' })

      call(:get, base)

      expect(response).to have_http_status(:ok)
      rows = response.parsed_body['payload'].index_by { |row| row['name'] }
      expect(rows['pedido_enviado']).to include('friendly_name' => 'Pedido enviado', 'fields' => { '1' => 'cliente.primeiro_nome' },
                                                'system_owner' => nil)
      expect(rows['agendamento_ao_marcar_v1']).to include('friendly_name' => 'agendamento_ao_marcar_v1', 'system_owner' => 'agendamento',
                                                          'profile_id' => nil)
      expect(rows[csat['name']]['system_owner']).to eq('satisfacao')
    end

    # #1465: a campanha mostra "vai a foto aprovada" só quando o arquivo do topo está mesmo guardado no perfil.
    it 'traz o nome do arquivo do topo guardado no perfil; sem arquivo, nil' do
      profile = WhatsappTemplateProfile.create!(account: account, inbox: inbox, waba_id: channel.waba_id, name: 'pedido_enviado',
                                                language: 'pt_BR', header_media: { 'file_name' => 'antigo.png' })
      profile.header_file.attach(io: StringIO.new('png'), filename: 'topo.png', content_type: 'image/png')
      WhatsappTemplateProfile.create!(account: account, inbox: inbox, waba_id: channel.waba_id, name: 'agendamento_ao_marcar_v1',
                                      language: 'pt_BR', header_media: { 'file_name' => 'so-no-json.png' })

      call(:get, base)

      rows = response.parsed_body['payload'].index_by { |row| row['name'] }
      expect(rows['pedido_enviado']['header_file_name']).to eq('topo.png')
      expect(rows['agendamento_ao_marcar_v1']['header_file_name']).to be_nil
      expect(rows[csat['name']]['header_file_name']).to be_nil
    end

    # A prévia da campanha mostra a foto aprovada: link de leitura assinado, só para foto.
    it 'traz o link assinado da foto do topo guardada; documento e vídeo ficam sem link' do
      foto = WhatsappTemplateProfile.create!(account: account, inbox: inbox, waba_id: channel.waba_id, name: 'pedido_enviado', language: 'pt_BR')
      foto.header_file.attach(io: StringIO.new('png'), filename: 'topo.png', content_type: 'image/png')
      pdf = WhatsappTemplateProfile.create!(account: account, inbox: inbox, waba_id: channel.waba_id, name: 'agendamento_ao_marcar_v1',
                                            language: 'pt_BR')
      pdf.header_file.attach(io: StringIO.new('pdf'), filename: 'tabela.pdf', content_type: 'application/pdf')

      call(:get, base)

      rows = response.parsed_body['payload'].index_by { |row| row['name'] }
      expect(rows['pedido_enviado']['header_file_preview_url']).to start_with('http').and include('topo.png')
      expect(rows['agendamento_ao_marcar_v1']['header_file_preview_url']).to be_nil
      expect(rows[csat['name']]['header_file_preview_url']).to be_nil
    end

    # #1338: a saúde de cada modelo (últimos 30 dias) vem na própria lista, sem uma chamada por modelo.
    it 'traz a saúde de cada modelo: envios, entregas, leituras, respostas e custo' do
      conversation = create(:conversation, account: account, inbox: inbox)
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, status: :read,
                       created_at: 2.days.ago, additional_attributes: { 'template_params' => { 'name' => 'pedido_enviado', 'language' => 'pt_BR' } })
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, created_at: 1.day.ago)

      call(:get, base)

      rows = response.parsed_body['payload'].index_by { |row| row['name'] }
      expect(rows['pedido_enviado']['health']).to include('days' => 30, 'sent' => 1, 'delivered' => 1, 'read' => 1, 'replied' => 1,
                                                          'average_reply_rate' => nil)
      expect(rows['pedido_enviado']['health']['cost']).to include('currency' => 'BRL')
      expect(rows['agendamento_ao_marcar_v1']['health']).to include('sent' => 0, 'cost' => nil)
    end

    it 'o perfil sobrevive ao sync que regrava a lista inteira' do
      WhatsappTemplateProfile.create!(account: account, inbox: inbox, waba_id: channel.waba_id, name: 'pedido_enviado',
                                      language: 'pt_BR', friendly_name: 'Pedido enviado')
      sync_url = "https://graph.facebook.com/v14.0/#{channel.waba_id}/message_templates"
      stub_request(:get, sync_url).with(query: hash_including({})).to_return(status: 200, headers: json, body: { data: [mine] }.to_json)

      call(:get, base, { refresh: true })

      expect(response.parsed_body['payload']).to contain_exactly(a_hash_including('name' => 'pedido_enviado', 'friendly_name' => 'Pedido enviado'))
    end

    # #1382: o "Atualizar" diz a verdade quando o sync não deu certo, em vez da lista antiga como se fosse nova.
    it 'atualizar que falha responde com o código (502 quando a Meta não respondeu, 422 nos outros)' do
      sync_url = "https://graph.facebook.com/v14.0/#{channel.waba_id}/message_templates"
      stub_request(:get, sync_url).with(query: hash_including({})).to_return(status: 503)
      allow_any_instance_of(Whatsapp::Providers::WhatsappCloudService).to receive(:sleep) # rubocop:disable RSpec/AnyInstance

      call(:get, base, { refresh: true })

      expect(response).to have_http_status(:bad_gateway)
      expect(response.parsed_body).to include('error' => 'sync_failed', 'code' => 'meta_unreachable',
                                              'message' => I18n.t('whatsapp_templates.errors.sync_failed', locale: 'pt_BR'))

      stub_request(:get, sync_url).with(query: hash_including({})).to_return(status: 401, headers: json,
                                                                             body: { error: { code: 190 } }.to_json)
      call(:get, base, { refresh: true })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('code' => 'permission_denied',
                                              'message' => I18n.t('whatsapp_templates.errors.permission_denied', locale: 'pt_BR'))
    end

    it 'caixa que não é do WhatsApp oficial com WABA não tem a API' do
      other = create(:channel_whatsapp, account: account, provider: 'default', sync_templates: false, validate_provider_config: false).inbox

      call(:get, "/api/v1/accounts/#{account.id}/inboxes/#{other.id}/whatsapp_templates")

      expect(response).to have_http_status(:not_found)
    end

    it 'agente comum, sem função, não vê' do
      agent = create(:user, account: account, role: :agent)
      create(:inbox_member, user: agent, inbox: inbox)

      call(:get, base, {}, user: agent)

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST create' do
    let(:params) do
      { template: { name: 'boas_vindas', language: 'pt_BR', category: 'MARKETING', friendly_name: 'Boas-vindas', waba_id: 'outra',
                    fields: { '1' => 'cliente.primeiro_nome' },
                    components: [{ type: 'BODY', text: 'Oi {{1}}, que bom te ver.', example: { body_text: [['Ana']] } }] } }
    end

    it 'cria na WABA da caixa (ignora WABA do pedido), grava o perfil e põe o modelo na lista' do
      stub_lookup('boas_vindas', [])
      post = stub_request(:post, templates_url).to_return(status: 200, headers: json, body: { id: '901', status: 'PENDING' }.to_json)

      call(:post, base, params)

      expect(response).to have_http_status(:created)
      expect(post).to have_been_requested.once
      expect(a_request(:post, templates_url).with { |request| JSON.parse(request.body).dig('components', 0, 'example', 'body_text') == [['Ana']] })
        .to have_been_made
      profile = WhatsappTemplateProfile.find_by!(inbox: inbox, name: 'boas_vindas')
      expect(profile).to have_attributes(waba_id: channel.waba_id, meta_template_id: '901', friendly_name: 'Boas-vindas', created_by_id: admin.id)
      expect(channel.reload.message_templates.pluck('name')).to include('boas_vindas')
    end

    # #1334: a campanha do carrossel usa a mesma mídia aprovada de cada cartão, guardada aqui na criação.
    it 'guarda o arquivo de cada cartão do carrossel no perfil, com a posição do cartão; arquivo de outra conta não entra' do
      stub_lookup('vitrine', [])
      stub_request(:post, templates_url).to_return(status: 200, headers: json, body: { id: '902', status: 'PENDING' }.to_json)
      blobs = %w[1 2].map do |numero|
        ActiveStorage::Blob.create_and_upload!(io: StringIO.new('png'), filename: "cartao-#{numero}.png", content_type: 'image/png',
                                               metadata: { 'account_id' => account.id })
      end
      card = { components: [{ type: 'HEADER', format: 'IMAGE', example: { header_handle: ['h'] } }, { type: 'BODY', text: 'Produto' },
                            { type: 'BUTTONS', buttons: [{ type: 'URL', text: 'Ver', url: 'https://loja.com' }] }] }
      template = { name: 'vitrine', language: 'pt_BR', category: 'MARKETING',
                   components: [{ type: 'BODY', text: 'Veja a vitrine.' }, { type: 'CAROUSEL', cards: [card, card] }],
                   card_media: blobs.each_with_index.map { |blob, index| { card_index: index, blob_signed_id: blob.signed_id } } }

      call(:post, base, { template: template })

      expect(response).to have_http_status(:created)
      profile = WhatsappTemplateProfile.find_by!(inbox: inbox, name: 'vitrine')
      expect([0, 1].map { |index| profile.card_file(index).filename.to_s }).to eq(%w[cartao-1.png cartao-2.png])
      # A lista devolve os arquivos guardados de cada cartão: a campanha mostra "vai a foto aprovada".
      call(:get, base)
      row = response.parsed_body['payload'].find { |item| item['name'] == 'vitrine' }
      expect(row['card_media'].map { |media| media.slice('card_index', 'file_name') })
        .to eq([{ 'card_index' => 0, 'file_name' => 'cartao-1.png' }, { 'card_index' => 1, 'file_name' => 'cartao-2.png' }])
      # #1716: a galeria da conversa mostra a foto e manda a referência do arquivo, conferida no envio como escolhida.
      expect(row['card_media'].map { |media| ActiveStorage::Blob.find_signed(media['blob_signed_id']) }).to eq(blobs)
      expect(row['card_media']).to all(include('preview_url' => a_string_starting_with('http')))

      foreign = ActiveStorage::Blob.create_and_upload!(io: StringIO.new('x'), filename: 'a.png', metadata: { 'account_id' => account.id + 1 })
      call(:post, base, { template: template.merge(name: 'vitrine_2', card_media: [{ card_index: 0, blob_signed_id: foreign.signed_id }]) })
      expect(response.parsed_body['error']).to eq('media_invalid')

      # Posição fora de 0 a 9, ou o arquivo que já está em outro modelo: recusado antes da Meta.
      fresh = ActiveStorage::Blob.create_and_upload!(io: StringIO.new('x'), filename: 'b.png', metadata: { 'account_id' => account.id })
      [{ card_index: 10, blob_signed_id: fresh.signed_id }, { card_index: 0, blob_signed_id: blobs.first.signed_id }].each do |media|
        call(:post, base, { template: template.merge(name: 'vitrine_3', card_media: [media]) })
        expect(response.parsed_body['error']).to eq('media_invalid')
      end
    end

    it 'nome que já existe na WABA não cria de novo e avisa' do
      stub_lookup('boas_vindas', [{ 'id' => '5', 'name' => 'boas_vindas', 'language' => 'pt_BR' }])
      post = stub_request(:post, templates_url)

      call(:post, base, params)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('name_taken')
      expect(post).not_to have_been_requested
    end

    it 'perfil inválido é recusado antes de falar com a Meta' do
      call(:post, base, { template: params[:template].merge(friendly_name: 'x' * 121) })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('invalid_profile')
      expect(a_request(:any, graph_host)).not_to have_been_made
    end

    it 'arquivo de outra conta não entra no perfil' do
      blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new('x'), filename: 'a.png', metadata: { 'account_id' => account.id + 1 })

      call(:post, base, { template: params[:template].merge(header_media: { handle: 'h', blob_signed_id: blob.signed_id }) })

      expect(response.parsed_body['error']).to eq('media_invalid')
      expect(a_request(:any, graph_host)).not_to have_been_made
    end

    it 'não cria com o nome de um modelo do sistema' do
      call(:post, base, { template: params[:template].merge(name: 'agendamento_ao_marcar_v1') })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('system_template')
    end

    # #1418: produtos do catálogo só com a flag `whatsapp_campaign_products`; o servidor barra antes da Meta.
    it 'modelo com produtos do catálogo sem a flag: 422 products_disabled, sem chamar a Meta; com a flag, segue' do
      spm = [{ type: 'HEADER', format: 'PRODUCT' }, { type: 'BODY', text: 'Veja este produto.' },
             { type: 'BUTTONS', buttons: [{ type: 'SPM', text: 'Ver' }] }]
      card = { components: [{ type: 'HEADER', format: 'PRODUCT' }, { type: 'BUTTONS', buttons: [{ type: 'SPM', text: 'Ver' }] }] }
      cartoes = [{ type: 'BODY', text: 'Veja.' }, { type: 'CAROUSEL', cards: [card, card] }]

      [spm, cartoes].each do |components|
        call(:post, base, { template: params[:template].merge(name: 'vitrine', fields: {}, components: components) })
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body).to include('error' => 'products_disabled',
                                                'message' => I18n.t('whatsapp_templates.errors.products_disabled', locale: :pt_BR))
      end
      call(:patch, "#{base}/11", { template: { components: spm } })
      expect(response.parsed_body['error']).to eq('products_disabled')
      expect(a_request(:any, ->(uri) { uri.host == 'graph.facebook.com' })).not_to have_been_made

      account.enable_features!('whatsapp_campaign_products')
      stub_lookup('vitrine', [])
      stub_request(:post, templates_url).to_return(status: 200, headers: json, body: { id: '902', status: 'PENDING' }.to_json)
      call(:post, base, { template: params[:template].merge(name: 'vitrine', fields: {}, components: spm) })
      expect(response).to have_http_status(:created)
    end
  end

  # #1380: o pronto "Cobrança ou boleto" foi à Meta com COPY_CODE sem exemplo num aviso e voltou recusado. A forma que a
  # Meta exige é conferida aqui, antes de qualquer chamada à Graph.
  describe 'forma que a Meta exige' do
    let(:boleto_antigo) do
      [{ type: 'HEADER', format: 'DOCUMENT', example: { header_handle: ['h'] } },
       { type: 'BODY', text: 'Olá, {{1}}. O seu boleto vence hoje. O código está no botão.', example: { body_text: [['Ana']] } },
       { type: 'BUTTONS', buttons: [{ type: 'COPY_CODE' }] }]
    end

    it 'não cria o pronto antigo do boleto: 422 com o código, sem chamar a Meta' do
      call(:post, base, { template: { name: 'cobranca_ou_boleto', language: 'pt_BR', category: 'UTILITY', components: boleto_antigo } })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('error' => 'marketing_only', 'problems' => %w[marketing_only copy_code_example])
      expect(response.parsed_body['message']).to eq(I18n.t('whatsapp_templates.errors.marketing_only', locale: 'pt_BR'))
      expect(a_request(:any, graph_host)).not_to have_been_made
      expect(WhatsappTemplateProfile.where(inbox: inbox)).to be_empty
    end

    it 'não cria botão de site sem endereço nem de ligar sem número' do
      buttons = [{ type: 'URL', text: 'Ver', url: '' }, { type: 'PHONE_NUMBER', text: 'Ligar' }]
      call(:post, base, { template: { name: 'aviso', language: 'pt_BR', category: 'UTILITY',
                                      components: [{ type: 'BODY', text: 'Oi.' }, { type: 'BUTTONS', buttons: buttons }] } })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['problems']).to eq(%w[url_missing phone_missing])
      expect(a_request(:any, graph_host)).not_to have_been_made
    end

    it 'não altera o conteúdo para uma forma que a Meta recusa' do
      call(:patch, "#{base}/11", { template: { components: [{ type: 'BODY', text: 'Oi {{1}}, saiu.' },
                                                            { type: 'BUTTONS', buttons: [{ type: 'COPY_CODE', example: 'PIX 123' }] }] } })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['problems']).to eq(%w[marketing_only copy_code_example])
      expect(a_request(:any, graph_host)).not_to have_been_made
    end

    context 'when the template has a picture at the top and the edit brings no new file' do
      def photo
        mine.merge('id' => '16', 'name' => 'com_foto', 'status' => 'REJECTED',
                   'components' => [{ 'type' => 'HEADER', 'format' => 'IMAGE', 'example' => { 'header_handle' => ['4::velho'] } },
                                    { 'type' => 'BODY', 'text' => 'Olá {{1}}, veja.' }])
      end

      def edit
        { components: [{ type: 'HEADER', format: 'IMAGE' }, { type: 'BODY', text: 'Olá {{1}}, veja a novidade.' }] }
      end

      before { channel.update_columns(message_templates: [mine, photo]) } # rubocop:disable Rails/SkipsModelValidations

      it 'sobe de novo o arquivo guardado no perfil e manda o handle novo, nunca o velho' do
        profile = WhatsappTemplateProfile.create!(account: account, inbox: inbox, waba_id: channel.waba_id, name: 'com_foto', language: 'pt_BR')
        profile.header_file.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'topo.png', content_type: 'image/png')
        allow(GlobalConfigService).to receive(:load).and_call_original
        allow(GlobalConfigService).to receive(:load).with('WHATSAPP_APP_ID', '').and_return('app_1')
        stub_request(:post, "#{graph}/app_1/uploads").with(query: hash_including({}))
                                                     .to_return(status: 200, headers: json, body: { id: 'upload:s3' }.to_json)
        stub_request(:post, "#{graph}/upload:s3").to_return(status: 200, headers: json, body: { h: '4::novo' }.to_json)
        stub_lookup('com_foto', [photo])
        edit_request = stub_request(:post, "#{graph}/16").to_return(status: 200, headers: json, body: { success: true }.to_json)

        call(:patch, "#{base}/16", { template: edit })

        expect(response).to have_http_status(:ok)
        expect(edit_request.with { |request| JSON.parse(request.body).dig('components', 0, 'example', 'header_handle') == ['4::novo'] })
          .to have_been_requested
      end

      it 'sem arquivo guardado, pede o arquivo (422) sem falar com a Meta' do
        call(:patch, "#{base}/16", { template: edit })

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('media_required')
        expect(a_request(:any, graph_host)).not_to have_been_made
      end
    end
  end

  describe 'PATCH update e DELETE destroy' do
    it 'edita o conteúdo na Meta, volta para análise e grava o perfil' do
      stub_lookup('pedido_enviado', [mine])
      edit = stub_request(:post, "#{graph}/11").to_return(status: 200, headers: json, body: { success: true }.to_json)

      call(:patch, "#{base}/11", { template: { friendly_name: 'Pedido', components: [{ type: 'BODY', text: 'Oi {{1}}, saiu.' }] } })

      expect(response).to have_http_status(:ok)
      expect(edit).to have_been_requested.once
      expect(response.parsed_body).to include('status' => 'PENDING', 'friendly_name' => 'Pedido')
    end

    it 'só o nome amigável não chama a Meta' do
      call(:patch, "#{base}/11", { template: { friendly_name: 'Pedido' } })

      expect(response).to have_http_status(:ok)
      expect(a_request(:any, graph_host)).not_to have_been_made
    end

    # #1394: a Meta não aceita trocar a categoria de um modelo que já existe (vimos num recusado, na conta 16).
    context 'when the edit changes the category' do
      let(:rejected) { mine.merge('id' => '17', 'name' => 'cobranca_ou_boleto', 'status' => 'REJECTED', 'category' => 'MARKETING') }

      before { channel.update_columns(message_templates: [mine, rejected]) } # rubocop:disable Rails/SkipsModelValidations

      it 'recusa com 422 e o código, sem chamar a Graph nem mexer no perfil' do
        call(:patch, "#{base}/17", { template: { category: 'UTILITY', friendly_name: 'Boleto',
                                                 components: [{ type: 'BODY', text: 'Olá {{1}}, seu boleto saiu. Qualquer dúvida, responda.' }] } })

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body).to include('error' => 'category_change_not_allowed',
                                                'message' => I18n.t('whatsapp_templates.errors.category_change_not_allowed', locale: 'pt_BR'))
        expect(a_request(:any, graph_host)).not_to have_been_made
        expect(WhatsappTemplateProfile.where(inbox: inbox)).to be_empty
      end

      it 'a mesma categoria passa e não vai para a Meta (a edição nunca manda categoria)' do
        stub_lookup('cobranca_ou_boleto', [rejected])
        edit = stub_request(:post, "#{graph}/17").to_return(status: 200, headers: json, body: { success: true }.to_json)

        call(:patch, "#{base}/17", { template: { category: 'MARKETING',
                                                 components: [{ type: 'BODY', text: 'Olá {{1}}, seu boleto saiu. Qualquer dúvida, responda.' }] } })

        expect(response).to have_http_status(:ok)
        expect(edit.with { |request| JSON.parse(request.body).keys == ['components'] }).to have_been_requested.once
        expect(response.parsed_body).to include('category' => 'MARKETING', 'status' => 'PENDING')
      end
    end

    it 'a recusa da Meta sem texto nosso não chega crua à tela' do
      stub_lookup('pedido_enviado', [mine])
      # Subcódigo que não temos mapeado (o da troca de categoria a Meta não documenta).
      meta_text = 'Você não pode atualizar uma categoria de modelo aprovada'
      stub_request(:post, "#{graph}/11")
        .to_return(status: 400, headers: json, body: { error: { code: 100, error_subcode: 2_388_999, error_user_msg: meta_text } }.to_json)

      call(:patch, "#{base}/11", { template: { components: [{ type: 'BODY', text: 'Oi {{1}}, saiu. Qualquer dúvida, responda.' }] } })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('error' => 'meta_refused', 'code' => 'meta_text',
                                              'message' => I18n.t('whatsapp_templates.errors.meta_text', locale: 'pt_BR'))
      expect(response.parsed_body['message']).not_to include('categoria de modelo aprovada')
    end

    it 'apaga na Meta só aquele modelo, tira da lista e apaga o perfil' do
      WhatsappTemplateProfile.create!(account: account, inbox: inbox, waba_id: channel.waba_id, name: 'pedido_enviado', language: 'pt_BR')
      stub_lookup('pedido_enviado', [mine])
      delete = stub_request(:delete, templates_url).with(query: { 'name' => 'pedido_enviado', 'hsm_id' => '11' })
                                                   .to_return(status: 200, headers: json, body: { success: true }.to_json)

      call(:delete, "#{base}/11")

      expect(response).to have_http_status(:no_content)
      expect(delete).to have_been_requested.once
      expect(WhatsappTemplateProfile.where(inbox: inbox)).to be_empty
      expect(channel.reload.message_templates.pluck('name')).not_to include('pedido_enviado')
    end

    it 'modelo do sistema não é alterado nem apagado' do
      call(:delete, "#{base}/12")
      expect(response.parsed_body['error']).to eq('system_template')

      call(:patch, "#{base}/13", { template: { friendly_name: 'x' } })
      expect(response.parsed_body['error']).to eq('system_template')
      expect(a_request(:any, graph_host)).not_to have_been_made
    end

    it 'modelo com campanha agendada não é apagado nem alterado (422 com o uso)' do
      create(:campaign, account: account, inbox: inbox, title: 'Black Friday', message: 'x', campaign_type: :one_off,
                        scheduled_at: 1.day.from_now, template_params: { 'name' => 'pedido_enviado', 'language' => 'pt_BR' })

      call(:delete, "#{base}/11")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('in_use')
      expect(response.parsed_body.dig('usage', 'campaigns', 0, 'title')).to eq('Black Friday')
      expect(a_request(:any, graph_host)).not_to have_been_made
    end

    # #1332: a campanha parou por causa do modelo (pausa aberta). Corrigir o modelo é o caminho para ela voltar; apagar
    # continua barrado (o nome fica preso 30 dias e a campanha não sairia mais).
    context 'with a campaign stopped by the template' do
      before do
        campaign = create(:campaign, account: account, inbox: inbox, title: 'Lembrete de outubro', message: 'x', campaign_type: :one_off,
                                     scheduled_at: 1.hour.ago, template_params: { 'name' => 'pedido_enviado', 'language' => 'pt_BR' })
        CampaignPauses::Pauser.new(campaign, source: 'template', reason_code: 'template_not_approved',
                                             details: { template_name: 'pedido_enviado', status: 'REJECTED' }).perform
      end

      it 'deixa corrigir o modelo' do
        stub_lookup('pedido_enviado', [mine])
        edit = stub_request(:post, "#{graph}/11").to_return(status: 200, body: { success: true }.to_json, headers: json)
        components = [{ 'type' => 'BODY', 'text' => 'Olá {{1}}, seu pedido saiu. Qualquer dúvida, responda.' }]

        call(:patch, "#{base}/11", { template: { components: components } })

        expect(response).to have_http_status(:ok)
        expect(edit).to have_been_made.once
        call(:get, "#{base}/11/usage")
        expect(response.parsed_body).to include('in_use' => true, 'blocks_change' => false)
        expect(response.parsed_body.dig('campaigns', 0)).to include('title' => 'Lembrete de outubro', 'paused' => true)
      end

      it 'não deixa apagar' do
        call(:delete, "#{base}/11")

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('in_use')
        expect(a_request(:any, graph_host)).not_to have_been_made
      end

      it 'uma campanha agendada que não parou continua travando alterar' do
        create(:campaign, account: account, inbox: inbox, title: 'Black Friday', message: 'x', campaign_type: :one_off,
                          scheduled_at: 1.day.from_now, template_params: { 'name' => 'pedido_enviado', 'language' => 'pt_BR' })

        call(:patch, "#{base}/11", { template: { components: [{ 'type' => 'BODY', 'text' => 'Olá {{1}}, ok.' }] } })

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('in_use')
      end
    end

    it 'id que não está na lista da caixa é 404' do
      call(:delete, "#{base}/999")

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST media' do
    it 'sobe o arquivo na Meta pelo tipo do conteúdo (não o declarado) e devolve o handle e a referência' do
      allow(GlobalConfigService).to receive(:load).and_call_original
      allow(GlobalConfigService).to receive(:load).with('WHATSAPP_APP_ID', '').and_return('app_1')
      stub_request(:post, "#{graph}/app_1/uploads").with(query: hash_including('file_type' => 'image/png'))
                                                   .to_return(status: 200, headers: json, body: { id: 'upload:s1' }.to_json)
      stub_request(:post, "#{graph}/upload:s1").to_return(status: 200, headers: json, body: { h: '4::h' }.to_json)
      file = Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/avatar.png'), 'application/pdf')

      post "#{base}/media", params: { file: file }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include('handle' => '4::h', 'content_type' => 'image/png')
      expect(ActiveStorage::Blob.find_signed(response.parsed_body['blob_signed_id'])).to be_present
    end
  end

  # #2370: o WhatsApp não entrega HEVC. O .mov do iPhone é convertido para MP4 H.264 num job (dezenas de segundos em
  # produção, mais que o limite do pedido); a subida volta 202 e a tela consulta o `poll_url`.
  describe 'POST media: vídeo convertido fora do pedido', :aggregate_failures do
    def hevc_mov(dir)
      path = File.join(dir, 'IMG_0001.MOV')
      system('ffmpeg', '-v', 'error', '-y', '-f', 'lavfi', '-i', 'testsrc=size=640x360:rate=30:duration=2', '-c:v', 'libx265',
             '-tag:v', 'hvc1', '-pix_fmt', 'yuv420p', '-f', 'mov', path, exception: true)
      Rack::Test::UploadedFile.new(path, 'video/quicktime')
    end

    def post_hevc
      Dir.mktmpdir { |dir| post "#{base}/media", params: { file: hevc_mov(dir) }, headers: admin.create_new_auth_token }
    end

    before do
      allow(GlobalConfigService).to receive(:load).and_call_original
      allow(GlobalConfigService).to receive(:load).with('WHATSAPP_APP_ID', '').and_return('app_1')
    end

    it '.mov em HEVC: 202 sem falar com a Meta; o job converte, sobe e a consulta devolve o MP4 em H.264' do
      session = stub_request(:post, "#{graph}/app_1/uploads").with(query: hash_including('file_type' => 'video/mp4', 'file_name' => 'IMG_0001.mp4'))
                                                             .to_return(status: 200, headers: json, body: { id: 'upload:v1' }.to_json)
      stub_request(:post, "#{graph}/upload:v1").to_return(status: 200, headers: json, body: { h: '4::v' }.to_json)

      post_hevc

      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body['status']).to eq('pending')
      expect(a_request(:any, graph_host)).not_to have_been_made
      poll_url = response.parsed_body['poll_url']
      get poll_url, headers: admin.create_new_auth_token
      expect(response.parsed_body['status']).to eq('pending')

      perform_enqueued_jobs(only: Whatsapp::Templates::VideoConversionJob)
      get poll_url, headers: admin.create_new_auth_token

      expect(response.parsed_body['status']).to eq('done')
      result = response.parsed_body['result']
      expect(result).to include('handle' => '4::v', 'content_type' => 'video/mp4', 'file_name' => 'IMG_0001.mp4')
      expect(session).to have_been_made.once
      ActiveStorage::Blob.find_signed(result['blob_signed_id']).open do |file|
        expect(Whatsapp::Templates::VideoForMeta.probe(file.path)).to include(video: 'h264', pix_fmt: 'yuv420p')
      end
      expect(ActiveStorage::Blob.where('metadata LIKE ?', '%video_conversion%')).to be_empty
    end

    it 'a Meta recusando a subida: a consulta devolve failed com o texto traduzido, e o original é apagado' do
      stub_request(:post, "#{graph}/app_1/uploads").with(query: hash_including({}))
                                                   .to_return(status: 500, headers: json, body: { error: { message: 'x' } }.to_json)

      post_hevc
      poll_url = response.parsed_body['poll_url']
      perform_enqueued_jobs(only: Whatsapp::Templates::VideoConversionJob)
      get poll_url, headers: admin.create_new_auth_token

      expect(response.parsed_body['status']).to eq('failed')
      expect(response.parsed_body['message']).to eq(I18n.t("whatsapp_templates.errors.#{response.parsed_body['error']}", locale: :pt_BR))
      expect(ActiveStorage::Blob.where('metadata LIKE ?', '%video_conversion%')).to be_empty
    end

    it 'a conversão é só de quem subiu: outra pessoa da conta recebe 404' do
      post_hevc
      other = create(:user, account: account, role: :administrator)

      get response.parsed_body['poll_url'], headers: other.create_new_auth_token

      expect(response).to have_http_status(:not_found)
    end

    it '.mov que o ffprobe não lê: recusa no pedido com video_unreadable, sem job' do
      fake = "\x00\x00\x00\x14ftypqt  \x00\x00\x00\x00qt  ".b + ('x' * 64)
      file = Rack::Test::UploadedFile.new(StringIO.new(fake), 'video/quicktime', original_filename: 'falso.mov')

      post "#{base}/media", params: { file: file }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('error' => 'video_unreadable',
                                              'message' => I18n.t('whatsapp_templates.errors.video_unreadable', locale: :pt_BR))
      expect(Whatsapp::Templates::VideoConversionJob).not_to have_been_enqueued
    end
  end

  # #1334: tipo e tamanho que a Meta aceita, conferidos no servidor antes de subir (página "Media" da Meta, 13/10/2026):
  # JPG/PNG até 5 MB, MP4 até 16 MB, PDF até 100 MB. A foto do cartão da campanha sobe por aqui também.
  describe 'POST media: tipo e tamanho' do
    it 'recusa arquivo de tipo que a Meta não aceita, sem falar com a Meta' do
      file = Rack::Test::UploadedFile.new(StringIO.new('texto'), 'text/plain', original_filename: 'nota.txt')

      post "#{base}/media", params: { file: file }, headers: admin.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('media_invalid')
      expect(a_request(:any, graph_host)).not_to have_been_made
    end

    it 'recusa arquivo que só tem nome de foto (o conteúdo manda, não o nome nem o tipo declarado)' do
      file = Rack::Test::UploadedFile.new(StringIO.new('não sou foto'), 'image/png', original_filename: 'falsa.png')

      post "#{base}/media", params: { file: file }, headers: admin.create_new_auth_token

      expect(response.parsed_body['error']).to eq('media_invalid')
      expect(a_request(:any, graph_host)).not_to have_been_made
    end

    it 'recusa foto acima de 5 MB, sem falar com a Meta' do
      big = StringIO.new("\x89PNG\r\n\x1A\n".b + ('0' * (5.megabytes + 1)))
      file = Rack::Test::UploadedFile.new(big, 'image/png', original_filename: 'grande.png')

      post "#{base}/media", params: { file: file }, headers: admin.create_new_auth_token

      expect(response.parsed_body['error']).to eq('media_invalid')
      expect(a_request(:any, graph_host)).not_to have_been_made
    end
  end

  describe 'GET usage' do
    it 'mostra campanhas, avisos do agendamento e follow-ups pendentes que usam o modelo' do
      create(:campaign, account: account, inbox: inbox, title: 'Campanha', message: 'x', campaign_type: :one_off,
                        scheduled_at: 1.day.from_now, template_params: { 'name' => 'pedido_enviado', 'language' => 'pt_br' })
      world = build_booking_world(account: account)
      world.profile.update_columns(enabled: true, page_version: 2, notice_inbox_id: inbox.id, notice_preset: 'light', # rubocop:disable Rails/SkipsModelValidations
                                   notice_templates: { 'booked' => { 'name' => 'pedido_enviado', 'language' => 'pt_BR' },
                                                       'day_before' => { 'name' => 'pedido_enviado', 'language' => 'pt_BR' } })
      Crm::FollowUp.create!(account: account, card: world.card, inbox: inbox, title: 'Retorno', due_at: 1.day.from_now, status: :pending,
                            metadata: { 'template_name' => 'pedido_enviado', 'template_language' => 'pt_BR' })

      call(:get, "#{base}/11/usage")

      body = response.parsed_body
      expect(body['campaigns'].pluck('title')).to eq(['Campanha'])
      expect(body['booking_pages']).to eq([{ 'id' => world.profile.id, 'title' => world.profile.title }])
      expect(body['follow_ups'].pluck('title')).to eq(['Retorno'])
      expect(body).to include('uso_oculto' => false, 'in_use' => true)
    end
  end

  # Mesmo token em duas contas (como em produção): a conta A não alcança a WABA da B por nenhum endpoint.
  # #1419: os erros que saem por `rescue_from` vinham em inglês para quem usa o painel em pt_BR, porque o `rescue_from`
  # roda depois que o `around_action` de idioma já devolveu o idioma padrão.
  describe 'idioma das mensagens de erro' do
    let(:account) { create(:account, locale: 'en') }

    before { admin.update!(ui_settings: { 'locale' => 'pt_BR' }) }

    def message_for(key)
      I18n.t("whatsapp_templates.errors.#{key}", locale: 'pt_BR')
    end

    it 'nome repetido sai no idioma da pessoa' do
      stub_lookup('boas_vindas', [{ 'id' => '5', 'name' => 'boas_vindas', 'language' => 'pt_BR' }])

      call(:post, base, { template: { name: 'boas_vindas', language: 'pt_BR', category: 'MARKETING',
                                      components: [{ type: 'BODY', text: 'Oi, que bom te ver.' }] } })

      expect(response.parsed_body).to include('error' => 'name_taken', 'message' => message_for('name_taken'))
    end

    it 'a recusa da Meta sem texto nosso sai no idioma da pessoa' do
      stub_lookup('pedido_enviado', [mine])
      stub_request(:post, "#{graph}/11")
        .to_return(status: 400, headers: json, body: { error: { code: 100, error_subcode: 2_388_999, error_user_msg: 'x' } }.to_json)

      call(:patch, "#{base}/11", { template: { components: [{ type: 'BODY', text: 'Oi {{1}}, saiu. Qualquer dúvida, responda.' }] } })

      expect(response.parsed_body).to include('error' => 'meta_refused', 'message' => message_for('meta_text'))
    end

    # O texto nosso para uma recusa da Meta (aqui, o nome preso) é montado no serviço com o idioma da conta; a tela
    # mostra o da pessoa.
    it 'a recusa da Meta com texto nosso sai no idioma da pessoa, não no da conta' do
      stub_lookup('pedido_enviado', [mine])
      stub_request(:post, "#{graph}/11")
        .to_return(status: 400, headers: json, body: { error: { code: 100, error_subcode: 2_388_023, message: 'x' } }.to_json)

      call(:patch, "#{base}/11", { template: { components: [{ type: 'BODY', text: 'Oi {{1}}, saiu. Qualquer dúvida, responda.' }] } })

      expect(response.parsed_body).to include('error' => 'meta_refused', 'code' => 'name_held', 'message' => message_for('name_held'))
    end

    it 'modelo que não está na lista sai no idioma da pessoa' do
      call(:patch, "#{base}/999", { template: { friendly_name: 'Outro' } })

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to include('error' => 'template_not_found', 'message' => message_for('template_not_found'))
    end

    it 'Meta fora do ar sai no idioma da pessoa' do
      stub_request(:get, templates_url).with(query: hash_including('name' => 'pedido_enviado')).to_return(status: 503)

      call(:delete, "#{base}/11")

      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body).to include('error' => 'meta_unreachable', 'message' => message_for('meta_unreachable'))
    end
  end

  describe 'isolamento entre contas' do # rubocop:disable RSpec/MultipleMemoizedHelpers
    let(:other_account) { create(:account) }
    let(:other_channel) do
      create(:channel_whatsapp, account: other_account, provider: 'whatsapp_cloud', sync_templates: false,
                                validate_provider_config: false, message_templates: [])
    end
    let(:other_inbox) { other_channel.inbox }
    let(:other_template) { mine.merge('id' => '77', 'name' => 'da_conta_b') }
    let(:waba_b) { ->(uri) { uri.path.split('/').include?('waba_b') } }

    before do
      channel.update_columns(provider_config: channel.provider_config.merge('business_account_id' => 'waba_a', 'api_key' => 'shared')) # rubocop:disable Rails/SkipsModelValidations
      other_channel.update_columns(message_templates: [other_template], # rubocop:disable Rails/SkipsModelValidations
                                   provider_config: other_channel.provider_config.merge('business_account_id' => 'waba_b', 'api_key' => 'shared'))
      stub_request(:any, waba_b).to_raise(StandardError.new('WABA da outra conta'))
    end

    it 'nenhum endpoint da conta A abre a caixa da B' do
      other_base = "/api/v1/accounts/#{account.id}/inboxes/#{other_inbox.id}/whatsapp_templates"
      [[:get, other_base], [:post, other_base], [:patch, "#{other_base}/77"], [:delete, "#{other_base}/77"],
       [:get, "#{other_base}/77/usage"], [:post, "#{other_base}/media"]].each do |verb, path|
        call(verb, path, { template: { name: 'x' } })
        expect(response).to have_http_status(:not_found), "#{verb} #{path} devolveu #{response.status}"
      end
      expect(a_request(:any, waba_b)).not_to have_been_made
    end

    it 'na caixa da A, o id de um modelo da B não é encontrado, mesmo com WABA no pedido' do
      %w[77].each do |id|
        call(:patch, "#{base}/#{id}", { template: { category: 'UTILITY', waba_id: 'waba_b', business_account_id: 'waba_b' } })
        expect(response).to have_http_status(:not_found)
        call(:delete, "#{base}/#{id}", { waba_id: 'waba_b' })
        expect(response).to have_http_status(:not_found)
        call(:get, "#{base}/#{id}/usage")
        expect(response).to have_http_status(:not_found)
      end
      expect(a_request(:any, waba_b)).not_to have_been_made
    end

    it 'mesmo se a lista da caixa A trouxesse o id da B, a Meta não confirma o id na WABA da A e nada é alterado' do
      channel.update_columns(message_templates: [other_template]) # rubocop:disable Rails/SkipsModelValidations
      stub_request(:get, "#{graph}/waba_a/message_templates")
        .with(query: hash_including({})).to_return(status: 200, headers: json, body: { data: [] }.to_json)
      edit = stub_request(:post, "#{graph}/77")
      delete = stub_request(:delete, "#{graph}/waba_a/message_templates")

      # Conteúdo, não categoria: a categoria não vai para a Meta na edição (#1394).
      call(:patch, "#{base}/77", { template: { components: [{ type: 'BODY', text: 'Oi, tudo certo. Qualquer dúvida, responda.' }] } })
      expect(response).to have_http_status(:not_found)
      call(:delete, "#{base}/77")
      expect(response).to have_http_status(:not_found)

      expect(edit).not_to have_been_requested
      expect(delete).not_to have_been_requested
      expect(a_request(:any, waba_b)).not_to have_been_made
    end
  end

  def graph_host
    ->(uri) { uri.host == 'graph.facebook.com' }
  end
end
