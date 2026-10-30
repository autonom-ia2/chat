require 'rails_helper'

# Comentários do Instagram pela Graph do login do Instagram (#2196): o token da caixa vai só na query da chamada e
# nunca no log; erro da Meta vira Result com o código, para quem chama separar falta de permissão de falha passageira.
RSpec.describe Instagram::CommentsClient do
  subject(:client) { described_class.new(channel) }

  let(:channel) { create(:channel_instagram, instagram_id: '17841400000000001') }
  let(:base) { 'https://graph.instagram.com/v22.0' }
  let(:json) { { 'Content-Type' => 'application/json' } }

  it 'lista os comentários da mídia com as respostas, seguindo o cursor' do
    request = stub_request(:get, "#{base}/1790000000000001/comments")
              .with(query: hash_including('access_token' => channel.access_token, 'after' => 'C1', 'limit' => '25'))
              .to_return(status: 200, headers: json,
                         body: { data: [{ id: '1', text: 'Tem M?' }], paging: { cursors: { after: 'C2' }, next: 'x' } }.to_json)

    result = client.comments('1790000000000001', after: 'C1')

    expect(result.ok).to be(true)
    expect(result.data['data'].first['text']).to eq('Tem M?')
    expect(request.with(query: hash_including('fields' => described_class::COMMENT_FIELDS))).to have_been_made
  end

  it 'responde em público, oculta, apaga e manda a resposta no privado pelo id do comentário' do
    reply = stub_request(:post, "#{base}/1/replies").with(query: { 'access_token' => channel.access_token },
                                                          body: 'message=Temos%20sim',
                                                          headers: { 'Content-Type' => 'application/x-www-form-urlencoded' })
                                                    .to_return(status: 200, body: { id: '2' }.to_json, headers: json)
    hide = stub_request(:post, "#{base}/1").with(query: hash_including('hide' => 'true'))
                                           .to_return(status: 200, body: { success: true }.to_json, headers: json)
    delete = stub_request(:delete, "#{base}/1").with(query: hash_including({}))
                                               .to_return(status: 200, body: { success: true }.to_json, headers: json)
    private_reply = stub_request(:post, "#{base}/17841400000000001/messages")
                    .with(query: hash_including({}), body: { recipient: { comment_id: '1' }, message: { text: 'Oi!' } }.to_json)
                    .to_return(status: 200, body: { recipient_id: '9', message_id: 'm1' }.to_json, headers: json)

    expect(client.reply('1', 'Temos sim').data).to eq('id' => '2')
    expect(client.hide('1', hidden: true).ok).to be(true)
    expect(client.delete('1').ok).to be(true)
    expect(client.private_reply('1', 'Oi!').data).to eq('recipient_id' => '9', 'message_id' => 'm1')
    expect([reply, hide, delete, private_reply]).to all(have_been_requested.once)
  end

  it 'falta de permissão vem com o código e sem o token no log' do
    stub_request(:get, %r{#{base}/1790000000000001/comments})
      .to_return(status: 400, headers: json, body: { error: { code: 10, message: "sem permissão #{channel.access_token}" } }.to_json)
    allow(Rails.logger).to receive(:warn)

    result = client.comments('1790000000000001')

    expect(result.ok).to be(false)
    expect(result.scope_error?).to be(true)
    expect(Rails.logger).to have_received(:warn).with(satisfy { |line| line.exclude?(channel.access_token) })
  end

  # #2327: a mensagem de erro da Meta pode repetir o texto enviado; o log leva só o caminho, o HTTP e o código.
  it 'erro da Meta não leva a mensagem dela ao log' do
    error = { error: { code: 100, message: 'Texto: Oi, Carla' } }
    stub_request(:post, "#{base}/1/replies").with(query: hash_including({})).to_return(status: 400, headers: json, body: error.to_json)
    allow(Rails.logger).to receive(:warn)

    expect(client.reply('1', 'Oi, Carla')).to have_attributes(ok: false, error_code: 100)
    expect(Rails.logger).to have_received(:warn).with('[InstagramComments] POST 1/replies http=400 code=100')
  end

  it 'falha de rede vira resultado passageiro, sem levantar' do
    stub_request(:get, %r{#{base}/1790000000000001/comments}).to_raise(Errno::ECONNRESET)

    result = client.comments('1790000000000001')

    expect(result.ok).to be(false)
    expect(result.transient?).to be(true)
  end

  it 'erro de rede vira resultado sem http_code; erro nosso sobe' do
    stub_request(:post, %r{graph\.instagram\.com/v22\.0/18000000000000001/replies}).to_timeout
    expect(client.reply('18000000000000001', 'Oi')).to have_attributes(ok: false, http_code: nil)

    [Net::ProtocolError, Zlib::DataError, HTTParty::RedirectionTooDeep.new(nil)].each do |error|
      allow(HTTParty).to receive(:post).and_raise(error)
      expect(client.reply('18000000000000001', 'Oi')).to have_attributes(ok: false, http_code: nil)
    end

    allow(HTTParty).to receive(:post).and_raise(NoMethodError)
    expect { client.reply('18000000000000001', 'Oi') }.to raise_error(NoMethodError)
  end
end
