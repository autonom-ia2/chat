require 'rails_helper'

RSpec.describe Meta::WabaDatasetClient do
  let(:token) { "EAAG#{'t' * 40}" }
  let(:endpoint) { 'https://graph.facebook.com/v22.0/111/dataset' }
  let(:client) { described_class.new(access_token: token, waba_id: '111', api_version: 'v22.0') }

  it 'returns the dataset the WABA already has, without creating one' do
    get = stub_request(:get, endpoint).with(headers: { 'Authorization' => "Bearer #{token}" })
                                      .to_return(status: 200, body: { data: [{ id: '1000000000000001' }] }.to_json,
                                                 headers: { 'Content-Type' => 'application/json' })
    post = stub_request(:post, endpoint)

    expect(client.find_or_create.dataset_id).to eq('1000000000000001')
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

  # #2799: Integer() accepts surrounding spaces, which would then land in the Graph path.
  it 'refuses a WABA id with spaces or that is not positive, without calling Meta' do
    [' 111', '111 ', '1 11', '0', '-5', ''].each do |waba_id|
      result = described_class.new(access_token: token, waba_id: waba_id, api_version: 'v22.0').find_or_create

      expect(result.error).to eq('invalid_waba_id'), waba_id.inspect
    end
  end

  # #2799: 100/33 on the WABA itself means the token cannot reach it: reconnect, not "no dataset".
  it 'marks a WABA the token cannot reach (100/33) as access denied' do
    stub_request(:get, endpoint).to_return(status: 400, body: { error: { message: 'does not exist', code: 100, error_subcode: 33 } }.to_json)

    expect(client.find_or_create).to have_attributes(access_denied: true, transient: false)
  end

  # #2799: only a network failure is passing; a bug in our code must not be retried as if it were.
  it 'lets an error of our own code raise instead of calling it a passing failure' do
    allow(HTTParty).to receive(:get).and_raise(NoMethodError)

    expect { client.find_or_create }.to raise_error(NoMethodError)
  end

  it 'reads the listing even without a JSON Content-Type' do
    stub_request(:get, endpoint).to_return(status: 200, body: { data: [{ id: '42' }] }.to_json, headers: { 'Content-Type' => 'text/javascript' })

    expect(client.find_or_create.dataset_id).to eq('42')
  end

  it 'marks a refused permission as access denied and a rate limit, 429 or 5xx as passing' do
    stub_request(:get, endpoint).to_return(
      { status: 403, body: { error: { message: 'no permission', code: 200 } }.to_json },
      { status: 400, body: { error: { message: 'slow down', code: 4 } }.to_json },
      { status: 429, body: '' },
      { status: 502, body: 'bad gateway' },
      { status: 400, body: { error: { message: 'unsupported', code: 100 } }.to_json }
    )

    expect(client.find_or_create).to have_attributes(error: 'meta_error_200: no permission', transient: false, access_denied: true)
    expect(client.find_or_create.transient).to be(true)
    expect(client.find_or_create.transient).to be(true)
    expect(client.find_or_create.transient).to be(true)
    expect(client.find_or_create).to have_attributes(transient: false, access_denied: false)
  end

  it 'turns a network failure into a passing error result' do
    [Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNRESET, OpenSSL::SSL::SSLError, EOFError].each do |error|
      stub_request(:get, endpoint).to_raise(error)

      result = client.find_or_create

      expect([result.dataset_id, result.error.present?, result.transient]).to eq([nil, true, true]), error.name
    end
  end
end
