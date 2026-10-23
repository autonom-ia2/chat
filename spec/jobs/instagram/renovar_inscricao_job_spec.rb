require 'rails_helper'

RSpec.describe Instagram::RenovarInscricaoJob do
  def url_de(channel)
    "https://graph.instagram.com/v22.0/#{channel.instagram_id}/subscribed_apps"
  end

  # Com a lista exata de campos: a inscrição troca a lista inteira na Meta.
  def stub_inscricao(channel, status:, body:)
    stub_request(:post, url_de(channel))
      .with(query: { access_token: channel[:access_token], subscribed_fields: Channel::Instagram::SUBSCRIBED_FIELDS })
      .to_return(status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  # A criação da caixa já se inscreve (after_create_commit): a contagem começa depois dela.
  def criar_caixas(quantidade)
    create_list(:channel_instagram, quantidade).tap { WebMock.reset_executed_requests! }
  end

  it 'refaz a inscrição de cada caixa com token válido, com todos os campos' do
    caixas = criar_caixas(2)
    stubs = caixas.map { |channel| stub_inscricao(channel, status: 200, body: { success: true }) }

    described_class.perform_now

    expect(stubs).to all(have_been_requested.once)
  end

  it 'deixa de fora a caixa com token vencido ou revogado' do
    channel = criar_caixas(1).first
    channel.revoke_access!
    stub = stub_inscricao(channel, status: 200, body: { success: true })

    described_class.perform_now

    expect(stub).not_to have_been_requested
  end

  it 'registra a recusa da Meta com o id do canal e sem o token' do
    channel = create(:channel_instagram)
    stub_inscricao(channel, status: 400, body: { error: { message: 'Invalid parameter' } })
    allow(Rails.logger).to receive(:warn)

    described_class.perform_now

    expect(Rails.logger).to have_received(:warn).with(a_string_including("channel #{channel.id}", 'HTTP 400'))
    expect(Rails.logger).not_to have_received(:warn).with(a_string_including(channel[:access_token]))
  end

  it 'trata resposta 200 sem success true como recusa' do
    channel = create(:channel_instagram)
    stub_inscricao(channel, status: 200, body: { success: false })
    allow(Rails.logger).to receive(:warn)

    described_class.perform_now

    expect(Rails.logger).to have_received(:warn).with(a_string_including("channel #{channel.id}"))
  end

  it 'aceita a confirmação da Meta mesmo sem o tipo application/json' do
    channel = criar_caixas(1).first
    stub_request(:post, url_de(channel)).with(query: hash_including({}))
                                        .to_return(status: 200, body: '{"success":true}', headers: { 'Content-Type' => 'text/javascript' })
    allow(Rails.logger).to receive(:info)

    described_class.perform_now

    expect(Rails.logger).to have_received(:info).with("[#{described_class.name}] 1 de 1 caixas inscritas")
  end

  it 'segue para a próxima caixa quando uma falha na rede' do
    primeira, segunda = criar_caixas(2)
    stub_request(:post, url_de(primeira)).with(query: hash_including({})).to_raise(Errno::ECONNRESET)
    stub = stub_inscricao(segunda, status: 200, body: { success: true })
    allow(Rails.logger).to receive(:error)
    allow(Rails.logger).to receive(:warn)
    rastreador = instance_double(ChatwootExceptionTracker, capture_exception: true)
    allow(ChatwootExceptionTracker).to receive(:new).and_return(rastreador)

    described_class.perform_now

    expect(stub).to have_been_requested.once
    expect(Rails.logger).to have_received(:error).with("[#{described_class.name}] channel #{primeira.id}: Errno::ECONNRESET")
    expect(rastreador).to have_received(:capture_exception)
    expect(Rails.logger).to have_received(:warn).with("[#{described_class.name}] 1 de 2 caixas inscritas")
  end
end
