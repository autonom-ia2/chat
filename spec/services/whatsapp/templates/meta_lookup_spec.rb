require 'rails_helper'

# #1382: a consulta do disparo traz id e parameter_format (o item vai para a lista que o envio lê) e, se a Graph recusar
# um campo, pergunta de novo com os campos do #1329.
RSpec.describe Whatsapp::Templates::MetaLookup do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:url) { %r{/#{channel.waba_id}/message_templates} }
  let(:json) { { 'Content-Type' => 'application/json' } }
  let(:item) { { 'id' => '1', 'name' => 'aviso', 'language' => 'pt_BR', 'status' => 'APPROVED', 'parameter_format' => 'NAMED' } }

  it 'pede id e parameter_format' do
    request = stub_request(:get, url).with(query: hash_including('name' => 'aviso', 'fields' => described_class::FIELDS))
                                     .to_return(status: 200, headers: json, body: { data: [item] }.to_json)

    expect(described_class.new(channel: channel, name: 'aviso').templates).to eq([item])
    expect(request).to have_been_requested.once
    expect(described_class::FIELDS.split(',')).to include('id', 'parameter_format', 'status', 'components')
  end

  it 'campo recusado (400, código 100): pergunta de novo com os campos de antes' do
    stub_request(:get, url).with(query: hash_including('fields' => described_class::FIELDS))
                           .to_return(status: 400, headers: json, body: { error: { code: 100 } }.to_json)
    base = stub_request(:get, url).with(query: hash_including('fields' => described_class::BASE_FIELDS))
                                  .to_return(status: 200, headers: json, body: { data: [item.except('id')] }.to_json)

    expect(described_class.new(channel: channel, name: 'aviso').templates).to eq([item.except('id')])
    expect(base).to have_been_requested.once
  end

  it 'outro erro: nil (o disparo cai na lista guardada)' do
    stub_request(:get, url).to_return(status: 500, headers: json, body: {}.to_json)

    expect(described_class.new(channel: channel, name: 'aviso').templates).to be_nil
  end
end
