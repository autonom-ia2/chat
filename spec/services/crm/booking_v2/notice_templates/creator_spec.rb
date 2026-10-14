require 'rails_helper'

# Criar o modelo de um aviso na Meta (#1272), com a Meta falsa (WebMock): cria, não duplica (na caixa, na Meta, depois
# de recusa por nome usado), erro de permissão com texto próprio, texto da Meta sem o token e Meta fora do ar.
RSpec.describe Crm::BookingV2::NoticeTemplates::Creator do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false) }
  let(:inbox) { channel.inbox }
  let(:templates_url) { "https://graph.facebook.com/v14.0/#{channel.provider_config['business_account_id']}/message_templates" }
  let(:catalog) { Crm::BookingV2::NoticeTemplates::Catalog }
  let(:token) { channel.template_access_token }
  let(:json) { { 'Content-Type' => 'application/json' } }

  before do
    channel.update_columns(message_templates: []) # rubocop:disable Rails/SkipsModelValidations
    stub_request(:get, templates_url).with(query: hash_including({})).to_return(status: 200, body: { data: [] }.to_json, headers: json)
  end

  def stub_create(status: 200, body: { id: 'tpl1', status: 'PENDING', category: 'UTILITY' })
    stub_request(:post, templates_url).to_return(status: status, body: body.to_json, headers: json)
  end

  def create_for(kind)
    described_class.new(inbox: inbox).create(kind)
  end

  it 'envia à Meta o modelo pronto do aviso e o põe na caixa como em aprovação' do
    stub_create

    create_for('booked')

    expect(a_request(:post, templates_url).with do |request|
      body = JSON.parse(request.body)
      body['name'] == 'agendamento_ao_marcar_v1' && body['language'] == 'pt_BR' && body['category'] == 'UTILITY' &&
        body['components'].first['text'] == catalog.body_for('booked') &&
        body['components'].first.dig('example', 'body_text').first.size == 3 &&
        request.headers['Authorization'] == "Bearer #{token}"
    end).to have_been_made.once
    expect(catalog.meta_states(inbox.reload)).to eq(
      'booked' => { 'state' => 'pending', 'reason' => nil, 'name' => 'agendamento_ao_marcar_v1', 'language' => 'pt_BR' }
    )
  end

  it 'os textos prontos usam só {{1}}, {{2}} e {{3}}, levam o link e não começam nem terminam em variável' do
    catalog.kinds.each do |kind|
      body = catalog.body_for(kind)
      fake = { 'components' => [{ 'type' => 'BODY', 'text' => body }] }
      expect(Crm::BookingV2::Notices::Route.fillable_template?(fake)).to be(true)
      expect(body).to include('{{1}}', '{{2}}', '{{3}}')
      expect(body).not_to end_with('}}')
      expect(body).not_to start_with('{{')
    end
  end

  it 'não cria de novo o modelo que já está na caixa' do
    channel.update_columns(message_templates: [{ 'name' => 'agendamento_ao_marcar_v1', 'language' => 'pt_BR', 'status' => 'APPROVED' }]) # rubocop:disable Rails/SkipsModelValidations
    post = stub_create

    create_for('booked')

    expect(post).not_to have_been_requested
  end

  it 'não cria de novo o modelo que já existe na Meta: só passa a constar na caixa, com o motivo da recusa' do
    stub_request(:get, templates_url).with(query: hash_including(name: 'agendamento_ao_marcar_v1')).to_return(
      status: 200, headers: json,
      body: { data: [{ name: 'agendamento_ao_marcar_v1', language: 'pt_BR', status: 'REJECTED', rejected_reason: 'INVALID_FORMAT' }] }.to_json
    )
    post = stub_create

    create_for('booked')

    expect(post).not_to have_been_requested
    expect(catalog.meta_states(inbox.reload)['booked']).to include('state' => 'rejected', 'reason' => 'INVALID_FORMAT')
  end

  it 'chamado duas vezes, cria uma vez só' do
    post = stub_create

    2.times { create_for('booked') }

    expect(post).to have_been_requested.once
  end

  it 'recusa por nome já usado, com o modelo já lá: conta como criado' do
    stub_create(status: 400, body: { error: { message: 'Duplicate', code: 100, error_subcode: 2_388_024 } })
    stub_request(:get, templates_url).with(query: hash_including(name: 'agendamento_ao_marcar_v1'))
                                     .to_return({ status: 200, body: { data: [] }.to_json, headers: json },
                                                { status: 200, headers: json,
                                                  body: { data: [{ id: '9', name: 'agendamento_ao_marcar_v1', language: 'pt_BR',
                                                                   status: 'PENDING' }] }.to_json })

    expect { create_for('booked') }.not_to raise_error
    expect(catalog.meta_states(inbox.reload)['booked']['state']).to eq('pending')
  end

  it 'conexão sem permissão na Meta (OAuthException 200 ou 10): texto próprio para reconectar a caixa' do
    [200, 10].each do |code|
      stub_create(status: 403, body: { error: { message: '(#200) Requires whatsapp_business_management permission', type: 'OAuthException',
                                                code: code } })

      expect { create_for('booked') }.to raise_error(described_class::MetaError) do |error|
        expect(error.message).to eq('A conexão deste WhatsApp não tem permissão para criar modelos. Reconecte a caixa em ' \
                                    'Configurações › Caixas de entrada e tente de novo.')
        expect(error.own_text).to be(true)
      end
    end
  end

  it 'recusa da Meta sobe com o texto dela, nunca com o token, e o log não leva o token' do
    stub_create(status: 400, body: { error: { message: "Invalid parameter #{token}", error_user_msg: 'O texto do modelo foi recusado.', code: 100 } })
    allow(Rails.logger).to receive(:warn)

    expect { create_for('booked') }.to raise_error(described_class::MetaError, 'O texto do modelo foi recusado.')
    expect(Rails.logger).not_to have_received(:warn).with(a_string_including(token))

    stub_create(status: 400, body: { error: { message: "bad token #{token}", code: 100 } })
    expect { create_for('booked') }.to raise_error(described_class::MetaError) { |error| expect(error.message).not_to include(token) }
  end

  it 'Meta fora do ar vira Unreachable (o job tenta de novo)' do
    stub_request(:post, templates_url).to_timeout

    expect { create_for('booked') }.to raise_error(described_class::Unreachable)
  end

  it 'Meta com erro 5xx, 429 ou corpo que não é JSON: Unreachable, não recusa' do
    [503, 429].each do |status|
      stub_request(:post, templates_url).to_return(status: status, body: '<html>erro</html>', headers: { 'Content-Type' => 'text/html' })

      expect { create_for('booked') }.to raise_error(described_class::Unreachable)
    end
  end

  it 'só WhatsApp Cloud: 360dialog não cria' do
    dialog = create(:channel_whatsapp, account: account, provider: 'default', validate_provider_config: false, sync_templates: false).inbox

    expect { described_class.new(inbox: dialog).create('booked') }.to raise_error(described_class::Unsupported)
  end
end
