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

  it 'erro que não é de campo (token inválido) segue o caminho de antes: nada muda na lista' do
    channel.update_columns(message_templates: [bare]) # rubocop:disable Rails/SkipsModelValidations
    stub_request(:get, url).with(query: hash_including('fields' => fields))
                           .to_return(status: 401, headers: json, body: { error: { code: 190 } }.to_json)

    channel.provider_service.sync_templates

    expect(channel.reload.message_templates).to eq([bare])
  end
end
