require 'rails_helper'

RSpec.describe Oauth::ClientMetadataDocument do
  let(:client_id) { 'https://emd.ia.br/oauth/cliente.json' }
  let(:redirect_uri) { 'https://emd.ia.br/painel/conexoes/volta' }
  let(:document) { { client_id: client_id, client_name: 'Em d.ia', redirect_uris: [redirect_uri], token_endpoint_auth_method: 'none' } }

  before { allow(Resolv).to receive(:getaddresses).with('emd.ia.br').and_return(['203.0.113.10']) }

  def stub_document(body = document.to_json, status: 200)
    stub_request(:get, client_id).to_return(status: status, body: body, headers: { 'Content-Type' => 'application/json' })
  end

  describe '.url?' do
    it 'accepts an https URL and nothing else' do
      expect(described_class.url?(client_id)).to be(true)
      expect(described_class.url?('http://emd.ia.br/oauth/cliente.json')).to be(false)
      expect(described_class.url?(SecureRandom.uuid)).to be(false)
      expect(described_class.url?("https://#{'a' * 300}.com")).to be(false)
    end
  end

  describe '.sync' do
    it 'creates a public client with the name and redirect URIs of the document' do
      stub_document

      application = described_class.sync(client_id)

      expect(application).to have_attributes(uid: client_id, name: 'Em d.ia', redirect_uri: redirect_uri, confidential: false, scopes: be_blank)
    end

    it 'does not create a client when the document names another client_id' do
      stub_document(document.merge(client_id: 'https://evil.example/doc.json').to_json)

      expect(described_class.sync(client_id)).to be_nil
      expect(Doorkeeper::Application.count).to eq(0)
    end

    it 'does not fetch a host that resolves to a private address' do
      allow(Resolv).to receive(:getaddresses).with('emd.ia.br').and_return(['203.0.113.10', '10.0.0.5'])
      request = stub_document

      expect(described_class.sync(client_id)).to be_nil
      expect(request).not_to have_been_requested
    end

    it 'does not fetch a host that resolves to loopback or link-local addresses' do
      %w[127.0.0.1 169.254.169.254 ::1 ::ffff:127.0.0.1 ::a00:1 64:ff9b::a00:1 2002:a00:1::1].each do |address|
        allow(Resolv).to receive(:getaddresses).with('emd.ia.br').and_return([address])

        expect(described_class.sync(client_id)).to be_nil
      end
    end

    it 'does not fetch a document on a port other than 443' do
      request = stub_request(:get, 'https://emd.ia.br:8443/oauth/cliente.json')

      expect(described_class.sync('https://emd.ia.br:8443/oauth/cliente.json')).to be_nil
      expect(request).not_to have_been_requested
    end

    it 'answers unknown client, without raising, for an id that is not a valid URL' do
      expect(described_class.sync('https://host invalido/doc.json')).to be_nil
    end

    it 'rejects a document that times out' do
      stub_request(:get, client_id).to_timeout

      expect(described_class.sync(client_id)).to be_nil
    end

    it 'does not fetch a rejected document again for a while' do
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
      stub_document(status: 404)

      2.times { described_class.sync(client_id) }

      expect(a_request(:get, client_id)).to have_been_made.once
    end

    it 'rejects redirect URIs that are not https' do
      stub_document(document.merge(redirect_uris: ['http://emd.ia.br/volta']).to_json)

      expect(described_class.sync(client_id)).to be_nil
    end

    it 'rejects a document larger than the cap' do
      stub_document(document.merge(padding: 'x' * 20.kilobytes).to_json)

      expect(described_class.sync(client_id)).to be_nil
    end

    it 'rejects a document that is not JSON or not found' do
      stub_document('not json')
      expect(described_class.sync(client_id)).to be_nil

      stub_document(status: 404)
      expect(described_class.sync(client_id)).to be_nil
    end

    it 'keeps a known client for an hour without fetching again' do
      stub_document
      described_class.sync(client_id)

      described_class.sync(client_id)

      expect(a_request(:get, client_id)).to have_been_made.once
    end

    it 'counts an unchanged document as checked, so it is not fetched on every authorization' do
      stub_document
      application = described_class.sync(client_id)
      application.update_column(:updated_at, 2.hours.ago) # rubocop:disable Rails/SkipsModelValidations

      2.times { described_class.sync(client_id) }

      expect(a_request(:get, client_id)).to have_been_made.twice
      expect(application.reload.updated_at).to be > 1.minute.ago
    end

    it 'refreshes a client after an hour and keeps the old one when the document cannot be read' do
      stub_document
      application = described_class.sync(client_id)
      application.update_column(:updated_at, 2.hours.ago) # rubocop:disable Rails/SkipsModelValidations

      stub_document(status: 500)

      expect(described_class.sync(client_id)).to eq(application)
      expect(application.reload.redirect_uri).to eq(redirect_uri)
    end
  end
end
