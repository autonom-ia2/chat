require 'rails_helper'

RSpec.describe TypesafeAi::Client do
  let(:api_key) { 'ts_test_key_not_real' }
  let(:base) { 'https://api.typesafe.ai' }

  it 'lists models with a bearer credential without exposing it in the response contract' do
    request = stub_request(:get, "#{base}/v1/models")
              .with(headers: { 'Authorization' => "Bearer #{api_key}" })
              .to_return(status: 200, body: { models: [{ name: 'jev-latest' }] }.to_json)

    expect(described_class.new(api_key: api_key).models).to eq([{ 'name' => 'jev-latest' }])
    expect(request).to have_been_requested.once
  end

  it 'posts the documented System One state, model and typed questions' do
    request = stub_request(:post, "#{base}/v1/systemone")
              .with do |http_request|
      body = JSON.parse(http_request.body)
      http_request.headers['Authorization'] == "Bearer #{api_key}" &&
        body == {
          'state' => { 'headers' => %w[SEGURADO MAIL] },
          'model' => 'jev-1.13.0',
          'questions' => { 'email' => { 'type' => 'choice', 'instructions' => 'Choose', 'criteria' => { 'a' => nil } } }
        }
    end.to_return(
      status: 200,
      body: { model: 'jev-1.13.0', answers: { email: { type: 'choice', choice: 'a', probabilities: { a: 1.0 }, confidence: 1.0 } },
              usage: { input_tokens: 20, output_tokens: 4 } }.to_json
    )

    result = described_class.new(api_key: api_key).evaluate(
      state: { headers: %w[SEGURADO MAIL] },
      model: 'jev-1.13.0',
      questions: { email: { type: 'choice', instructions: 'Choose', criteria: { a: nil } } }
    )

    expect(result.dig('answers', 'email', 'choice')).to eq('a')
    expect(request).to have_been_requested.once
  end

  it 'retries documented transient 429 and 529 responses before succeeding' do
    sleeper = instance_double(Proc)
    allow(sleeper).to receive(:call)
    request = stub_request(:get, "#{base}/v1/models").to_return(
      { status: 429, headers: { 'Retry-After' => '0.01' }, body: '{}' },
      { status: 529, body: '{}' },
      { status: 200, body: { models: [] }.to_json }
    )

    expect(described_class.new(api_key: api_key, sleeper: sleeper).models).to eq([])
    expect(request).to have_been_requested.times(3)
    expect(sleeper).to have_received(:call).twice
  end

  it 'returns a sanitized code for invalid credentials' do
    stub_request(:get, "#{base}/v1/models").to_return(status: 401, body: '{"detail":"do not expose"}')

    expect { described_class.new(api_key: api_key).models }
      .to raise_error(described_class::Error) { |error| expect([error.code, error.status]).to eq(['typesafe_invalid_key', 401]) }
  end

  it 'does not make a network call when no credential is configured' do
    expect { described_class.new(api_key: nil).models }
      .to raise_error(described_class::Error) { |error| expect(error.code).to eq('typesafe_not_configured') }
  end
end
