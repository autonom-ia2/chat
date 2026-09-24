require 'rails_helper'

RSpec.describe Autonomia::Prospecting::Providers::GooglePlacesProvider do
  it 'maps Google Places text search results to prospecting lead attributes' do
    stub_request(:post, 'https://places.googleapis.com/v1/places:searchText')
      .to_return(
        status: 200,
        body: {
          places: [
            {
              id: 'places/abc123',
              displayName: { text: 'Alpha Restaurante' },
              formattedAddress: 'Rua das Flores, 123, Sao Paulo - SP, Brasil',
              internationalPhoneNumber: '+55 11 99999-8888',
              websiteUri: 'https://alpha.example.com',
              location: { latitude: -23.55, longitude: -46.63 },
              rating: 4.7,
              userRatingCount: 231,
              types: ['restaurant']
            }
          ]
        }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

    results = described_class.new(
      query: 'restaurante',
      location: 'Sao Paulo',
      radius: 5000,
      limit: 1,
      api_key: 'test-key'
    ).search

    expect(results.first).to include(
      provider: 'google_places',
      provider_place_id: 'places/abc123',
      name: 'Alpha Restaurante',
      phone: '+55 11 99999-8888',
      website: 'https://alpha.example.com',
      city: 'Sao Paulo',
      state: 'SP',
      category: 'restaurant'
    )
  end

  # A chave é da plataforma (#683): o texto do Google fala do nosso projeto no Google Cloud e não chega ao cliente.
  describe 'erro do Google' do
    let(:provider) do
      described_class.new(query: 'restaurante', location: 'Sao Paulo', radius: 5000, limit: 1, api_key: 'chave', account_id: 42)
    end
    let(:service_disabled) do
      'Places API (New) has not been used in project 123456789 before or it is disabled. Enable it by visiting ' \
        'https://console.developers.google.com/apis/api/places.googleapis.com/overview?project=123456789'
    end

    def stub_google_error(status, message)
      stub_request(:post, described_class::ENDPOINT).to_return(status: status, body: { error: { message: message } }.to_json)
    end

    it 'devolve texto nosso no 403 e registra a mensagem do Google só no log do servidor' do
      stub_google_error(403, service_disabled)
      allow(Rails.logger).to receive(:warn)

      expect { provider.search }.to raise_error(Autonomia::Prospecting::SearchRunner::ProviderError) { |error|
        expect(error.message).to eq(described_class::UNAVAILABLE_MESSAGE)
        expect(error.message).not_to include('project')
      }
      expect(Rails.logger).to have_received(:warn).with(a_string_including('account_id=42', 'status=403', 'project 123456789'))
    end

    it 'diferencia cota estourada (429) de indisponível' do
      stub_google_error(429, 'Quota exceeded for quota metric')

      expect { provider.search }.to raise_error(Autonomia::Prospecting::SearchRunner::ProviderError, described_class::BUSY_MESSAGE)
    end

    it 'não repassa chave vencida (400) ao cliente' do
      stub_google_error(400, 'API key expired. Please renew the API key.')

      expect { provider.search }.to raise_error(Autonomia::Prospecting::SearchRunner::ProviderError, described_class::UNAVAILABLE_MESSAGE)
    end
  end
end
