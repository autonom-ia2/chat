require 'rails_helper'

RSpec.describe Meta::WabaDatasetClient do
  let(:token) { "EAAG#{'t' * 40}" }
  let(:endpoint) { 'https://graph.facebook.com/v22.0/111/dataset' }
  let(:client) { described_class.new(access_token: token, waba_id: '111', api_version: 'v22.0') }

  it 'returns the dataset the WABA already has, without creating one' do
    get = stub_request(:get, endpoint).with(headers: { 'Authorization' => "Bearer #{token}" })
                                      .to_return(status: 200, body: { data: [{ id: '1341407110837470' }] }.to_json,
                                                 headers: { 'Content-Type' => 'application/json' })
    post = stub_request(:post, endpoint)

    expect(client.find_or_create.dataset_id).to eq('1341407110837470')
    expect(get).to have_been_requested.once
    expect(post).not_to have_been_requested
  end

  it 'creates the dataset when the WABA has none' do
    stub_request(:get, endpoint).to_return(status: 200, body: { data: [] }.to_json, headers: { 'Content-Type' => 'application/json' })
    post = stub_request(:post, endpoint).with(headers: { 'Authorization' => "Bearer #{token}" })
                                        .to_return(status: 200, body: { id: '999' }.to_json,
                                                   headers: { 'Content-Type' => 'application/json' })

    expect(client.find_or_create.dataset_id).to eq('999')
    expect(post).to have_been_requested.once
  end

  it 'reports a Meta refusal without trying to create and without leaking the token' do
    stub_request(:get, endpoint).to_return(status: 400, body: { error: { message: "bad #{token}", code: 100 } }.to_json)
    post = stub_request(:post, endpoint)

    result = client.find_or_create

    expect(result.dataset_id).to be_nil
    expect(result.error).to include('<REDACTED>')
    expect(result.error).not_to include(token)
    expect(post).not_to have_been_requested
  end

  it 'does not create a dataset when the listing comes back in an unexpected shape' do
    stub_request(:get, endpoint).to_return(status: 200, body: { foo: 1 }.to_json, headers: { 'Content-Type' => 'application/json' })
    post = stub_request(:post, endpoint)

    expect(client.find_or_create.error).to eq('unexpected_dataset_listing')
    expect(post).not_to have_been_requested
  end

  # Nothing is stubbed: a call to Meta would fail with WebMock's error instead of this one.
  it 'refuses a WABA id that is not a number, without calling Meta' do
    result = described_class.new(access_token: token, waba_id: '../me', api_version: 'v22.0').find_or_create

    expect(result.error).to eq('invalid_waba_id')
  end

  it 'turns a network failure into an error result' do
    stub_request(:get, endpoint).to_raise(Net::OpenTimeout)

    result = client.find_or_create

    expect(result.dataset_id).to be_nil
    expect(result.error).to be_present
  end
end
