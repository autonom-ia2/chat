require 'rails_helper'

RSpec.describe Autonomia::Insurance::Connector::Http do
  let(:base) { 'https://exemplo.lambda-url.us-east-1.on.aws/' }
  let(:credentials) { { provider: 'agger', username: 'c@x.com', password: 'segredo' } }

  before do
    stub_const('ENV', ENV.to_h.merge('INSURANCE_CONNECTOR_URL' => base, 'AWS_REGION' => 'us-east-1'))
    # A assinatura SigV4 usa a credencial da instância; no teste basta uma credencial estática.
    allow(Aws::InstanceProfileCredentials).to receive(:new)
      .and_return(Aws::Credentials.new('AKIAEXEMPLO', 'segredo-de-assinatura'))
  end

  def stub_connector(status:, body:)
    stub_request(:post, "#{base}v1/agger/connection")
      .to_return(status: status, body: body, headers: { 'Content-Type' => 'application/json' })
  end

  it 'signs the request, sends the credentials and returns the connector payload' do
    stub_connector(status: 200, body: { 'status' => 'ready', 'account_label' => 'CORRETORA X' }.to_json)

    expect(described_class.new.connection_status(**credentials)).to include('status' => 'ready')
    expect(
      a_request(:post, "#{base}v1/agger/connection")
        .with(headers: { 'Authorization' => %r{AWS4-HMAC-SHA256 Credential=AKIAEXEMPLO/.*lambda/aws4_request} },
              body: { username: 'c@x.com', password: 'segredo' }.to_json)
    ).to have_been_made
  end

  it 'maps HTTP status to the connector error kind' do
    {
      401 => :auth_required,
      422 => :validation,
      502 => :unavailable,
      504 => :timeout,
      500 => :protocol
    }.each do |code, kind|
      stub_connector(status: code, body: { 'error' => 'x' }.to_json)
      expect { described_class.new.connection_status(**credentials) }
        .to raise_error(an_object_having_attributes(kind: kind))
    end
  end

  it 'treats a non-JSON 200 as protocol so the ladder can step down' do
    stub_connector(status: 200, body: '<html>manutencao</html>')

    expect { described_class.new.connection_status(**credentials) }
      .to raise_error(an_object_having_attributes(kind: :protocol))
  end

  it 'fails as config when the connector URL is missing' do
    stub_const('ENV', ENV.to_h.except('INSURANCE_CONNECTOR_URL'))

    expect { described_class.new.connection_status(**credentials) }
      .to raise_error(an_object_having_attributes(kind: :config))
  end

  it 'never leaks the signed URL or the password in the error message' do
    stub_request(:post, "#{base}v1/agger/connection")
      .to_raise(SocketError.new("falhou em #{base}?X-Amz-Signature=abc"))

    expect { described_class.new.connection_status(**credentials) }
      .to raise_error(an_object_having_attributes(kind: :unavailable)) do |error|
        expect(error.message).not_to include('X-Amz-Signature')
        expect(error.message).not_to include('segredo')
      end
  end
end
