require 'rails_helper'

# Sync com `fields=` (#1330): toda página pede os campos, o que vier sem category/components não quebra quem lê a lista,
# e a Graph recusando um campo não para o sync (segue como antes, sem `fields=`).
RSpec.describe Whatsapp::Templates::SyncFields do
  let(:channel) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false,
                              message_templates: [])
  end
  let(:url) { "https://graph.facebook.com/v14.0/#{channel.waba_id}/message_templates" }
  let(:json) { { 'Content-Type' => 'application/json' } }
  let(:fields) { described_class::FIELDS }
  let(:complete) do
    { 'id' => '1', 'name' => 'pedido_enviado', 'language' => 'pt_BR', 'status' => 'REJECTED', 'category' => 'UTILITY',
      'rejected_reason' => 'INVALID_FORMAT', 'components' => [{ 'type' => 'BODY', 'text' => 'Olá {{1}}, seu pedido saiu.' }] }
  end
  let(:bare) { { 'id' => '2', 'name' => 'so_nome', 'language' => 'pt_BR', 'status' => 'APPROVED' } }

  def page(data, after = nil)
    body = { data: data }
    body[:paging] = { cursors: { after: after } } if after
    { status: 200, headers: json, body: body.to_json }
  end

  it 'fica à frente do módulo de voz do enterprise na cadeia do provider' do
    ancestors = Whatsapp::Providers::WhatsappCloudService.ancestors
    expect(ancestors.first).to eq(described_class)
    expect(ancestors.index(described_class)).to be < ancestors.index(Whatsapp::Providers::WhatsappCloudService)
  end

  it 'pede os campos em todas as páginas e guarda o que a Graph mandou, inclusive item sem category/components' do
    first = stub_request(:get, url).with(query: { 'fields' => fields }, headers: { 'Authorization' => 'Bearer test_key' })
                                   .to_return(page([complete], 'cursor-1'))
    second = stub_request(:get, url).with(query: { 'fields' => fields, 'after' => 'cursor-1' }).to_return(page([bare]))

    channel.provider_service.sync_templates

    expect(first).to have_been_requested.once
    expect(second).to have_been_requested.once
    expect(channel.reload.message_templates).to eq([complete, bare])
  end

  it 'pede no mínimo o que o agendamento e o envio leem' do
    expect(fields.split(',')).to include('id', 'name', 'language', 'status', 'category', 'components', 'rejected_reason',
                                         'parameter_format', 'quality_score', 'correct_category')
  end

  it 'quem lê a lista continua funcionando com o item sem category/components' do
    stub_request(:get, url).with(query: hash_including('fields' => fields)).to_return(page([complete, bare]))
    channel.provider_service.sync_templates
    inbox = channel.inbox

    expect(Crm::BookingV2::NoticeTemplates::Catalog.templates_of(inbox).size).to eq(2)
    params = { 'name' => 'so_nome', 'language' => 'pt_BR' }
    guard = Whatsapp::AuthenticationTemplateGuard.new(channel: channel, recipient: '5511999999999', template_params: params)
    expect(guard.send(:authentication_template?)).to be(false)
  end

  describe 'níveis de campos quando a Graph recusa um campo' do
    let(:minimal) { described_class::MINIMAL_FIELDS }
    let(:refused) { { status: 400, headers: json, body: { error: { code: 100, message: 'x' } }.to_json } }

    before do
      allow(Rails.logger).to receive(:warn)
      allow(Rails.logger).to receive(:error)
    end

    it 'full: com todos os campos aceitos, nada no log' do
      full = stub_request(:get, url).with(query: { 'fields' => fields }).to_return(page([complete]))

      channel.provider_service.sync_templates

      expect(full).to have_been_requested.once
      expect(Rails.logger).not_to have_received(:warn).with(a_string_including('sync_fields_refused'))
      expect(Rails.logger).not_to have_received(:error)
    end

    it 'minimal: recusou o conjunto completo, usa o mínimo estável em todas as páginas e avisa' do
      stub_request(:get, url).with(query: hash_including('fields' => fields)).to_return(refused)
      first = stub_request(:get, url).with(query: { 'fields' => minimal }).to_return(page([complete], 'cursor-1'))
      second = stub_request(:get, url).with(query: { 'fields' => minimal, 'after' => 'cursor-1' }).to_return(page([bare]))

      channel.provider_service.sync_templates

      expect(first).to have_been_requested.once
      expect(second).to have_been_requested.once
      expect(a_request(:get, url).with(query: hash_including('fields' => fields))).to have_been_made.once
      expect(channel.reload.message_templates).to eq([complete, bare])
      expect(Rails.logger).to have_received(:warn).with(a_string_including('fields_level=minimal'))
      expect(Rails.logger).not_to have_received(:error)
    end

    it 'none: recusou também o mínimo, sincroniza sem fields= em todas as páginas e registra erro' do
      stub_request(:get, url).with(query: hash_including('fields' => fields)).to_return(refused)
      stub_request(:get, url).with(query: hash_including('fields' => minimal)).to_return(refused)
      plain = stub_request(:get, url).with(query: {}).to_return(page([bare], 'cursor-1'))
      plain_second = stub_request(:get, url).with(query: { 'after' => 'cursor-1' }).to_return(page([complete]))

      channel.provider_service.sync_templates

      expect(plain).to have_been_requested.once
      expect(plain_second).to have_been_requested.once
      expect(a_request(:get, url).with(query: hash_including('fields' => minimal))).to have_been_made.once
      expect(channel.reload.message_templates).to eq([bare, complete])
      expect(Rails.logger).to have_received(:warn).with(a_string_including('fields_level=minimal'))
      expect(Rails.logger).to have_received(:error).with(a_string_including('fields_level=none'))
    end

    it 'o mínimo cobre o que o envio e o agendamento leem' do
      expect(minimal.split(',')).to contain_exactly('id', 'name', 'language', 'status', 'category', 'components', 'rejected_reason')
    end
  end

  # #1382: o sync é tudo ou nada e diz o que aconteceu.
  describe 'sync atômico e resultado' do
    let(:old) { { 'id' => '9', 'name' => 'antigo', 'language' => 'pt_BR', 'status' => 'APPROVED' } }

    before do
      channel.update_columns(message_templates: [old]) # rubocop:disable Rails/SkipsModelValidations
      allow(Rails.logger).to receive(:error)
    end

    it 'falha na página 2: não grava nada, mantém a lista anterior, loga erro e devolve meta_unreachable' do
      stub_request(:get, url).with(query: { 'fields' => fields }).to_return(page([complete], 'cursor-1'))
      stub_request(:get, url).with(query: { 'fields' => fields, 'after' => 'cursor-1' })
                             .to_return(status: 503, headers: json, body: { error: { code: 2 } }.to_json)

      result = channel.provider_service.sync_templates

      expect(result).not_to be_ok
      expect(result.code).to eq('meta_unreachable')
      expect(channel.reload.message_templates).to eq([old])
      expect(Rails.logger).to have_received(:error).with(a_string_including('sync_failed code=meta_unreachable', 'kept_previous_list=true'))
    end

    it 'token vencido (190): nada muda na lista e o resultado é permission_denied, sem o token no log' do
      stub_request(:get, url).with(query: hash_including('fields' => fields))
                             .to_return(status: 401, headers: json, body: { error: { code: 190, message: 'Bearer test_key' } }.to_json)

      result = channel.provider_service.sync_templates

      expect(result.code).to eq('permission_denied')
      expect(channel.reload.message_templates).to eq([old])
      expect(Rails.logger).not_to have_received(:error).with(a_string_including('test_key'))
    end

    it 'outro 4xx: meta_refused; rede caída: meta_unreachable; 2xx sem lista: unexpected_body' do
      stub_request(:get, url).with(query: hash_including('fields' => fields))
                             .to_return(status: 400, headers: json, body: { error: { code: 132 } }.to_json)
      expect(channel.provider_service.sync_templates.code).to eq('meta_refused')

      WebMock.reset!
      stub_request(:get, url).with(query: hash_including('fields' => fields)).to_raise(Net::OpenTimeout)
      expect(channel.provider_service.sync_templates.code).to eq('meta_unreachable')

      WebMock.reset!
      stub_request(:get, url).with(query: hash_including('fields' => fields)).to_return(status: 200, headers: json, body: {}.to_json)
      expect(channel.provider_service.sync_templates.code).to eq('unexpected_body')
      expect(channel.reload.message_templates).to eq([old])
    end

    it 'sucesso: devolve ok com a contagem, troca a lista e renova o carimbo' do
      stub_request(:get, url).with(query: { 'fields' => fields }).to_return(page([complete, bare]))

      result = channel.provider_service.sync_templates

      expect(result).to be_ok
      expect(result.count).to eq(2)
      expect(channel.reload.message_templates).to eq([complete, bare])
      expect(channel.message_templates_last_updated).to be_within(5.seconds).of(Time.current)
    end

    it 'a WABA sem nenhum modelo grava a lista vazia (a falha não é mais confundida com lista vazia)' do
      stub_request(:get, url).with(query: { 'fields' => fields }).to_return(page([]))

      expect(channel.provider_service.sync_templates).to be_ok
      expect(channel.reload.message_templates).to eq([])
    end

    it 'o que a tela gravou enquanto o sync esperava a Meta não é apagado pelo sync' do
      created = { 'id' => '77', 'name' => 'novo', 'language' => 'pt_BR', 'status' => 'PENDING' }
      stub_request(:get, url).with(query: { 'fields' => fields }).to_return do
        Whatsapp::Templates::ChannelList.upsert!(Channel::Whatsapp.find(channel.id), created)
        page([complete])
      end

      channel.provider_service.sync_templates

      expect(channel.reload.message_templates).to eq([complete, created])
    end
  end

  it 'erro que não é de campo (token inválido) segue o caminho de antes: nada muda na lista' do
    channel.update_columns(message_templates: [bare]) # rubocop:disable Rails/SkipsModelValidations
    stub_request(:get, url).with(query: hash_including('fields' => fields))
                           .to_return(status: 401, headers: json, body: { error: { code: 190 } }.to_json)

    channel.provider_service.sync_templates

    expect(channel.reload.message_templates).to eq([bare])
  end
end
