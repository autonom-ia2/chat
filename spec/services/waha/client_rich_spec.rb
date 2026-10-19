require 'rails_helper'

# chat#1709: envio nativo de mensagem rica pelo motor, com os payloads conferidos no WAHA 2026.9.2 GOWS.
RSpec.describe Waha::Client do
  let(:config) { class_double(Waha::Config, api_url: 'https://waha.example', api_key: 'test-key') }
  let(:client) { described_class.new(config: config) }
  let(:json) { { 'Content-Type' => 'application/json' } }

  it 'sends a list without a pre-generated id and returns what the engine answered' do
    list = { title: 'Qual horário?', button: 'Ver opções',
             sections: [{ title: 'Ver opções', rows: [{ title: 'Manhã', rowId: 'manha' }, { title: 'Tarde', rowId: 'tarde' }] }] }
    request = stub_request(:post, 'https://waha.example/api/sendList')
              .with(headers: { 'X-Api-Key' => 'test-key' },
                    body: { session: 'hybrid-5511', chatId: '5511937016094@c.us', message: list }.to_json)
              .to_return(status: 201, headers: json, body: { id: 'true_5511937016094@c.us_3EB0LIST' }.to_json)

    result = client.send_list(session: 'hybrid-5511', chat_id: '5511937016094@c.us', message: list)

    expect(request).to have_been_requested.once
    expect(result).to eq('id' => 'true_5511937016094@c.us_3EB0LIST')
  end

  it 'sends a location with the pre-generated id' do
    request = stub_request(:post, 'https://waha.example/api/sendLocation')
              .with(body: { session: 'hybrid-5511', chatId: '5511937016094@c.us', id: '3EB0LOC', latitude: -23.5489,
                            longitude: -46.6388, title: 'Unidade Centro' }.to_json)
              .to_return(status: 201, headers: json, body: {}.to_json)

    client.send_location(session: 'hybrid-5511', chat_id: '5511937016094@c.us', id: '3EB0LOC',
                         location: { latitude: -23.5489, longitude: -46.6388, title: 'Unidade Centro' })

    expect(request).to have_been_requested.once
  end

  it 'sends a contact card with the pre-generated id and accepts an empty answer' do
    contacts = [{ fullName: 'Recepção', phoneNumber: '+55 11 4000-0473', whatsappId: '551140000473' }]
    request = stub_request(:post, 'https://waha.example/api/sendContactVcard')
              .with(body: { session: 'hybrid-5511', chatId: '5511937016094@c.us', id: '3EB0VCF', contacts: contacts }.to_json)
              .to_return(status: 201, body: '')

    result = client.send_contact_vcard(session: 'hybrid-5511', chat_id: '5511937016094@c.us', id: '3EB0VCF', contacts: contacts)

    expect(request).to have_been_requested.once
    expect(result).to be_nil
  end

  it 'raises Error with the status when the engine refuses (sendButtons answers 501 in GOWS; the same path applies)' do
    stub_request(:post, 'https://waha.example/api/sendList').to_return(status: 501, body: 'not implemented by GOWS')

    expect { client.send_list(session: 's', chat_id: 'c@c.us', message: {}) }
      .to raise_error(described_class::Error) { |error| expect(error.status).to eq(501) }
  end
end
