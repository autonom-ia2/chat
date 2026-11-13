require 'rails_helper'

# #2907: a empresa tira o acesso do app. O token segue válido, mas a Graph responde 100/33 para o número e a WABA. A
# checagem de saúde precisa tratar isso como autorização e marcar a caixa "precisa reconectar" no segundo erro seguido.
RSpec.describe Whatsapp::AccessLoss::HealthCheck do
  let(:channel) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false).tap do |record|
      record.update!(provider_config: { 'api_key' => 'token', 'phone_number_id' => 'pnid', 'business_account_id' => 'waba',
                                        'source' => 'embedded_signup' })
    end
  end
  let(:graph) { 'https://graph.facebook.com/v24.0' }
  let(:json) { { 'Content-Type' => 'application/json' } }

  def graph_error(code:, subcode: nil)
    { status: 400, headers: json, body: { error: { message: 'Unsupported get request.', code: code, error_subcode: subcode }.compact }.to_json }
  end

  def stub_phone(response) = stub_request(:get, "#{graph}/pnid").with(query: hash_including({})).to_return(response)

  def stub_waba(response) = stub_request(:get, "#{graph}/waba").with(query: hash_including({})).to_return(response)

  def ok(body) = { status: 200, headers: json, body: body.to_json }

  def sync
    Whatsapp::HealthService.new(channel).sync_health_status!
  rescue Whatsapp::HealthService::ApiError
    nil
  end

  after { channel.reauthorized! }

  describe 'ApiError#authorization_error?' do
    it '100/33 (sem acesso ao objeto) conta como autorização; 190 continua contando; 100 sem o 33 não' do
      error = ->(code, subcode) { Whatsapp::HealthService::ApiError.new(message: 'x', http_status: 400, code: code, subcode: subcode) }

      expect(error.call(100, 33)).to be_authorization_error
      expect(error.call(190, nil)).to be_authorization_error
      expect(error.call(100, nil)).not_to be_authorization_error
      expect(error.call(100, 2_494_067)).not_to be_authorization_error
    end
  end

  it 'primeiro 100/33 não marca a caixa (pode ser passageiro); o segundo seguido marca "precisa reconectar"' do
    stub_phone(graph_error(code: 100, subcode: 33))

    sync
    expect(channel.reauthorization_required?).to be(false)

    sync
    expect(channel.reauthorization_required?).to be(true)
  end

  it 'erro de API comum (sem ser de autorização) não conta' do
    stub_phone(graph_error(code: 1))

    2.times { sync }

    expect(channel.authorization_error_count).to eq(0)
    expect(channel.reauthorization_required?).to be(false)
  end

  it 'número lido mas WABA com 100/33 também conta (o erro vem junto, sem estourar)' do
    stub_phone(ok('id' => 'pnid', 'status' => 'CONNECTED'))
    stub_waba(graph_error(code: 100, subcode: 33))

    2.times { sync }

    expect(channel.reauthorization_required?).to be(true)
  end

  it 'checagem boa depois da queda marcada pela contagem apaga o aviso e zera a contagem (o acesso voltou)' do
    2.times { channel.authorization_error! }
    stub_phone(ok('id' => 'pnid', 'status' => 'CONNECTED'))
    stub_waba(ok('id' => 'waba', 'name' => 'WABA'))

    sync

    expect(channel.reauthorization_required?).to be(false)
    expect(channel.authorization_error_count).to eq(0)
  end

  it 'aviso que veio do webhook da Meta (contagem 0) não é apagado por checagem boa: espera a reconexão' do
    channel.prompt_reauthorization!
    stub_phone(ok('id' => 'pnid', 'status' => 'CONNECTED'))
    stub_waba(ok('id' => 'waba', 'name' => 'WABA'))

    sync

    expect(channel.reauthorization_required?).to be(true)
  end

  it 'checagem boa no meio zera a contagem: dois erros separados por um acerto não marcam' do
    stub_phone(graph_error(code: 100, subcode: 33))
    sync
    stub_phone(ok('id' => 'pnid', 'status' => 'CONNECTED'))
    stub_waba(ok('id' => 'waba', 'name' => 'WABA'))
    sync
    stub_phone(graph_error(code: 100, subcode: 33))
    sync

    expect(channel.reauthorization_required?).to be(false)
  end
end
