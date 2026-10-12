require 'rails_helper'

# Cliente de modelos da Meta (#1330) com a Graph falsa (WebMock): cria sem duplicar, edita e apaga só o que é da WABA da
# caixa, consulta com motivo de recusa, sobe mídia pela Resumable Upload API, tenta de novo em 5xx/429, reconhece
# permissão pelo código e nunca devolve o token.
RSpec.describe Whatsapp::Templates::MetaClient do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false,
                              message_templates: [])
  end
  let(:inbox) { channel.inbox }
  let(:graph) { 'https://graph.facebook.com/v22.0' }
  let(:templates_url) { "#{graph}/#{channel.waba_id}/message_templates" }
  let(:token) { channel.template_access_token }
  let(:json) { { 'Content-Type' => 'application/json' } }
  let(:client) { described_class.new(inbox: inbox) }
  let(:body) do
    { name: 'pedido_enviado', language: 'pt_BR', category: 'UTILITY', waba_id: 'outra_waba',
      components: [{ type: 'BODY', text: 'Olá {{1}}, seu pedido saiu.', example: { body_text: [['Ana']] }, extra: 'x' }] }
  end
  let(:remote) { { 'id' => '777', 'name' => 'pedido_enviado', 'language' => 'pt_BR', 'status' => 'REJECTED', 'rejected_reason' => 'INVALID_FORMAT' } }

  before { allow(client).to receive(:sleep) }

  def stub_lookup(data)
    stub_request(:get, templates_url).with(query: hash_including('name' => 'pedido_enviado'))
                                     .to_return(status: 200, headers: json, body: { data: data }.to_json)
  end

  it 'só serve caixa do WhatsApp oficial (Cloud) com WABA gravada' do
    expect(described_class.supported?(inbox)).to be(true)
    channel.update_columns(provider_config: channel.provider_config.except('business_account_id')) # rubocop:disable Rails/SkipsModelValidations
    expect(described_class.supported?(inbox.reload)).to be(false)
    expect { described_class.new(inbox: inbox) }.to raise_error(described_class::Unsupported)
  end

  describe '#create' do
    it 'cria na WABA da caixa, com o token da caixa, só com as chaves que a Meta conhece' do
      stub_lookup([])
      post = stub_request(:post, templates_url).to_return(status: 200, headers: json, body: { id: '901', status: 'PENDING' }.to_json)

      outcome = client.create(body)

      expect(outcome.created).to be(true)
      expect(outcome.template).to include('id' => '901', 'name' => 'pedido_enviado', 'status' => 'PENDING')
      expect(a_request(:post, templates_url).with do |request|
        sent = JSON.parse(request.body)
        request.headers['Authorization'] == "Bearer #{token}" && !sent.key?('waba_id') &&
          sent['components'].first.keys.sort == %w[example text type]
      end).to have_been_made.once
      expect(post).to have_been_requested.once
    end

    it 'não duplica: nome e idioma que já existem na WABA voltam sem criar' do
      stub_lookup([remote])
      post = stub_request(:post, templates_url)

      outcome = client.create(body)

      expect(outcome.created).to be(false)
      expect(outcome.template['id']).to eq('777')
      expect(post).not_to have_been_requested
    end

    it 'tenta de novo quando a Meta responde 5xx ou 429, conferindo o nome antes de cada nova tentativa' do
      stub_lookup([])
      post = stub_request(:post, templates_url).to_return({ status: 503 }, { status: 429 },
                                                          { status: 200, headers: json, body: { id: '902' }.to_json })

      expect(client.create(body).template['id']).to eq('902')
      expect(post).to have_been_requested.times(3)
    end

    it 'envio que a rede cortou mas a Meta criou conta como criado por este pedido' do
      lookup = stub_request(:get, templates_url).with(query: hash_including('name' => 'pedido_enviado'))
                                                .to_return({ status: 200, headers: json, body: { data: [] }.to_json },
                                                           { status: 200, headers: json, body: { data: [remote] }.to_json })
      post = stub_request(:post, templates_url).to_return(status: 503)

      outcome = client.create(body)

      expect(outcome.created).to be(true)
      expect(outcome.template['id']).to eq('777')
      expect(post).to have_been_requested.once
      expect(lookup).to have_been_requested.times(2)
    end

    it 'desiste depois das tentativas com Unreachable' do
      stub_lookup([])
      stub_request(:post, templates_url).to_return(status: 500)

      expect { client.create(body) }.to raise_error(described_class::Unreachable)
    end

    it 'falta de permissão pelo código da Meta vira texto nosso' do
      stub_lookup([])
      stub_request(:post, templates_url).to_return(status: 403, headers: json, body: { error: { code: 200, message: 'perm' } }.to_json)

      expect { client.create(body) }.to raise_error(described_class::MetaError) { |error|
        expect(error.own_text).to be(true)
        expect(error.message).to eq(I18n.t('whatsapp_templates.errors.permission_denied', locale: 'pt_BR'))
      }
    end

    it 'modelo que sumiu ou número sem acesso (100/33) vira texto honesto para os dois casos, não o inglês técnico' do
      stub_lookup([])
      stub_request(:post, templates_url)
        .to_return(status: 400, headers: json,
                   body: { error: { code: 100, error_subcode: 33, message: 'Unsupported post request. Object does not exist' } }.to_json)

      expect { client.create(body) }.to raise_error(described_class::MetaError) { |error|
        expect(error.message).to eq(I18n.t('whatsapp_templates.errors.not_found_or_no_access', locale: 'pt_BR'))
      }
    end

    it 'nome repetido ou preso que a Meta recusa em inglês vira o nosso texto' do
      stub_lookup([])
      { 2_388_024 => 'name_taken', 2_388_023 => 'name_held' }.each do |subcode, key|
        stub_request(:post, templates_url)
          .to_return(status: 400, headers: json,
                     body: { error: { code: 100, error_subcode: subcode, error_user_msg: 'A template with this name exists' } }.to_json)

        expect { client.create(body) }.to raise_error(described_class::MetaError) { |error|
          expect(error.message).to eq(I18n.t("whatsapp_templates.errors.#{key}", locale: 'pt_BR'))
          expect(error.code).to eq(key)
        }
      end
    end

    it 'o texto da Meta vai sem o token, mesmo se ela o repetir' do
      stub_lookup([])
      stub_request(:post, templates_url)
        .to_return(status: 400, headers: json, body: { error: { code: 100, error_user_msg: "token #{token} inválido" } }.to_json)

      expect { client.create(body) }.to raise_error(described_class::MetaError) { |error|
        expect(error.message).to eq('token [token] inválido')
        expect(error.own_text).to be(false)
        expect(error.code).to eq('meta_text')
      }
    end
  end

  describe 'edição, consulta e remoção' do
    it 'consulta o modelo da WABA com o motivo de recusa' do
      lookup = stub_lookup([remote])

      expect(client.find('777', 'pedido_enviado')).to include('rejected_reason' => 'INVALID_FORMAT')
      expect(lookup.with(query: hash_including('fields' => Whatsapp::Templates::SyncFields::FIELDS))).to have_been_requested
    end

    it 'edita só depois de confirmar que o id é da WABA da caixa, mandando só componentes e validade (a categoria não muda na edição, #1394)' do
      stub_lookup([remote])
      edit = stub_request(:post, "#{graph}/777").to_return(status: 200, headers: json, body: { success: true }.to_json)

      client.update('777', 'pedido_enviado', { components: body[:components], name: 'outro', category: 'MARKETING' })

      expect(a_request(:post, "#{graph}/777").with { |request| JSON.parse(request.body).keys.sort == %w[components] })
        .to have_been_made.once
      expect(edit).to have_been_requested.once
    end

    it 'id que não está na WABA da caixa não é editado, apagado nem consultado' do
      stub_lookup([remote])
      edit = stub_request(:post, "#{graph}/999")
      delete = stub_request(:delete, templates_url)

      expect { client.update('999', 'pedido_enviado', { category: 'UTILITY' }) }.to raise_error(described_class::NotFound)
      expect { client.delete_by_id('999', 'pedido_enviado') }.to raise_error(described_class::NotFound)
      expect { client.find('999', 'pedido_enviado') }.to raise_error(described_class::NotFound)
      expect(edit).not_to have_been_requested
      expect(delete).not_to have_been_requested
    end

    it 'apagar que a rede cortou depois de a Meta apagar termina como apagado, sem repetir o DELETE' do
      stub_request(:get, templates_url).with(query: hash_including('name' => 'pedido_enviado'))
                                       .to_return({ status: 200, headers: json, body: { data: [remote] }.to_json },
                                                  { status: 200, headers: json, body: { data: [] }.to_json })
      delete = stub_request(:delete, templates_url).with(query: hash_including({})).to_return(status: 502)

      expect(client.delete_by_id('777', 'pedido_enviado')).to be(true)
      expect(delete).to have_been_requested.once
    end

    it 'apaga por id (um idioma) e por nome (todos os idiomas) na WABA da caixa' do
      stub_lookup([remote])
      by_id = stub_request(:delete, templates_url).with(query: { 'name' => 'pedido_enviado', 'hsm_id' => '777' })
                                                  .to_return(status: 200, headers: json, body: { success: true }.to_json)
      by_name = stub_request(:delete, templates_url).with(query: { 'name' => 'pedido_enviado' })
                                                    .to_return(status: 200, headers: json, body: { success: true }.to_json)

      client.delete_by_id('777', 'pedido_enviado')
      client.delete_by_name('pedido_enviado')

      expect(by_id).to have_been_requested.once
      expect(by_name).to have_been_requested.once
    end
  end

  describe '#upload_media' do
    let(:io) { StringIO.new('png-bytes') }

    before { allow(GlobalConfigService).to receive(:load).and_call_original }

    it 'abre a sessão no app e envia o arquivo com Authorization OAuth, devolvendo o handle' do
      allow(GlobalConfigService).to receive(:load).with('WHATSAPP_APP_ID', '').and_return('app_1')
      session = stub_request(:post, "#{graph}/app_1/uploads")
                .with(query: { 'file_name' => 'topo.png', 'file_length' => '9', 'file_type' => 'image/png' },
                      headers: { 'Authorization' => "OAuth #{token}" })
                .to_return(status: 200, headers: json, body: { id: 'upload:abc' }.to_json)
      upload = stub_request(:post, "#{graph}/upload:abc")
               .with(body: 'png-bytes', headers: { 'Authorization' => "OAuth #{token}", 'file_offset' => '0' })
               .to_return(status: 200, headers: json, body: { h: '4::handle' }.to_json)

      expect(client.upload_media(io: io, file_name: 'topo.png', content_type: 'image/png')).to eq('4::handle')
      expect(session).to have_been_requested.once
      expect(upload).to have_been_requested.once
    end

    it 'sem o app do WhatsApp configurado, não chama a Meta e diz o porquê' do
      allow(GlobalConfigService).to receive(:load).with('WHATSAPP_APP_ID', '').and_return('')

      expect { client.upload_media(io: io, file_name: 'topo.png', content_type: 'image/png') }
        .to raise_error(described_class::MetaError, I18n.t('whatsapp_templates.errors.app_not_configured', locale: 'pt_BR'))
    end

    it 'recusa tipo ou tamanho que a Meta não aceita antes de chamar a Meta' do
      expect { client.upload_media(io: io, file_name: 'a.gif', content_type: 'image/gif') }
        .to raise_error(described_class::MetaError, I18n.t('whatsapp_templates.errors.media_invalid', locale: 'pt_BR'))
    end
  end

  # Em produção um token serve caixas de várias contas (WABAs diferentes): cada caixa só alcança a própria WABA.
  describe 'isolamento entre contas com o mesmo token' do
    let(:other_account) { create(:account) }
    let(:other_waba) { ->(uri) { uri.path.split('/').include?('waba_b') } }
    let(:other_channel) do
      create(:channel_whatsapp, account: other_account, provider: 'whatsapp_cloud', sync_templates: false,
                                validate_provider_config: false, message_templates: [])
    end

    before do
      channel.update_columns(provider_config: channel.provider_config.merge('business_account_id' => 'waba_a', 'api_key' => 'shared')) # rubocop:disable Rails/SkipsModelValidations
      other_channel.update_columns(provider_config: other_channel.provider_config.merge('business_account_id' => 'waba_b', # rubocop:disable Rails/SkipsModelValidations
                                                                                        'api_key' => 'shared'))
      stub_request(:any, other_waba).to_raise(StandardError.new('WABA da outra conta'))
      stub_request(:get, "#{graph}/waba_a/message_templates")
        .with(query: hash_including({})).to_return(status: 200, headers: json, body: { data: [] }.to_json)
    end

    it 'a caixa da conta A nunca chama a WABA da B, nem com o id de um modelo da B' do
      client_a = described_class.new(inbox: channel.inbox.reload)
      allow(client_a).to receive(:sleep)
      stub_request(:post, "#{graph}/waba_a/message_templates").to_return(status: 200, headers: json, body: { id: '1' }.to_json)

      client_a.create(body)
      expect { client_a.update('b_template', 'pedido_enviado', { category: 'UTILITY' }) }.to raise_error(described_class::NotFound)
      expect { client_a.delete_by_id('b_template', 'pedido_enviado') }.to raise_error(described_class::NotFound)

      expect(a_request(:any, other_waba)).not_to have_been_made
      expect(a_request(:post, "#{graph}/waba_a/message_templates")).to have_been_made.once
    end
  end
end
