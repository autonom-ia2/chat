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
                [:delete, "#{base}/11", {}],
                [:post, "#{base}/12/duplicate", { template: { name: 'copia' } }]]

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

    it 'o perfil sobrevive ao sync que regrava a lista inteira' do
      WhatsappTemplateProfile.create!(account: account, inbox: inbox, waba_id: channel.waba_id, name: 'pedido_enviado',
                                      language: 'pt_BR', friendly_name: 'Pedido enviado')
      sync_url = "https://graph.facebook.com/v14.0/#{channel.waba_id}/message_templates"
      stub_request(:get, sync_url).with(query: hash_including({})).to_return(status: 200, headers: json, body: { data: [mine] }.to_json)

      call(:get, base, { refresh: true })

      expect(response.parsed_body['payload']).to contain_exactly(a_hash_including('name' => 'pedido_enviado', 'friendly_name' => 'Pedido enviado'))
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

    it 'id que não está na lista da caixa é 404' do
      call(:delete, "#{base}/999")

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST duplicate' do
    it 'duplica um modelo do sistema com outro nome' do
      stub_lookup('meu_aviso', [])
      post = stub_request(:post, templates_url).to_return(status: 200, headers: json, body: { id: '950' }.to_json)

      call(:post, "#{base}/12/duplicate", { template: { name: 'meu_aviso', friendly_name: 'Meu aviso' } })

      expect(response).to have_http_status(:created)
      expect(post).to have_been_requested.once
      expect(response.parsed_body).to include('name' => 'meu_aviso', 'system_owner' => nil, 'friendly_name' => 'Meu aviso')
    end

    it 'topo com mídia: sobe de novo o arquivo guardado no perfil e a cópia fica com o mesmo arquivo' do
      media = mine.merge('id' => '15', 'name' => 'com_foto',
                         'components' => [{ 'type' => 'HEADER', 'format' => 'IMAGE', 'example' => { 'header_handle' => ['https://x'] } },
                                          { 'type' => 'BODY', 'text' => 'Olá {{1}}, veja.' }])
      channel.update_columns(message_templates: [media]) # rubocop:disable Rails/SkipsModelValidations
      source = WhatsappTemplateProfile.create!(account: account, inbox: inbox, waba_id: channel.waba_id, name: 'com_foto', language: 'pt_BR')
      source.header_file.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'topo.png', content_type: 'image/png')
      allow(GlobalConfigService).to receive(:load).and_call_original
      allow(GlobalConfigService).to receive(:load).with('WHATSAPP_APP_ID', '').and_return('app_1')
      stub_request(:post, "#{graph}/app_1/uploads").with(query: hash_including({}))
                                                   .to_return(status: 200, headers: json, body: { id: 'upload:s2' }.to_json)
      stub_request(:post, "#{graph}/upload:s2").to_return(status: 200, headers: json, body: { h: '4::novo' }.to_json)
      stub_lookup('com_foto_2', [])
      stub_request(:post, templates_url).to_return(status: 200, headers: json, body: { id: '960' }.to_json)

      call(:post, "#{base}/15/duplicate", { template: { name: 'com_foto_2' } })

      expect(response).to have_http_status(:created)
      sent_handle = ->(request) { JSON.parse(request.body).dig('components', 0, 'example', 'header_handle') == ['4::novo'] }
      expect(a_request(:post, templates_url).with(&sent_handle)).to have_been_made
      expect(WhatsappTemplateProfile.find_by!(name: 'com_foto_2').header_file.blob).to eq(source.header_file.blob)
    end

    it 'topo com mídia sem arquivo novo pede o arquivo' do
      media = mine.merge('id' => '14', 'name' => 'com_foto',
                         'components' => [{ 'type' => 'HEADER', 'format' => 'IMAGE', 'example' => { 'header_handle' => ['https://x'] } }])
      channel.update_columns(message_templates: [media]) # rubocop:disable Rails/SkipsModelValidations

      call(:post, "#{base}/14/duplicate", { template: { name: 'com_foto_2' } })

      expect(response.parsed_body['error']).to eq('media_required')
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
       [:post, "#{other_base}/77/duplicate"], [:get, "#{other_base}/77/usage"], [:post, "#{other_base}/media"]].each do |verb, path|
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

      call(:patch, "#{base}/77", { template: { category: 'UTILITY' } })
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
