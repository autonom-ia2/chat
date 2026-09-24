require 'rails_helper'

RSpec.describe Autonomia::Prospecting::Providers::GooglePlacesProvider do
  let(:address_components) do
    [
      { longText: '123', shortText: '123', types: ['street_number'] },
      { longText: 'Rua das Flores', shortText: 'R. das Flores', types: ['route'] },
      { longText: 'Pinheiros', shortText: 'Pinheiros', types: %w[sublocality_level_1 sublocality political] },
      { longText: 'São Paulo', shortText: 'São Paulo', types: %w[locality political] },
      { longText: 'São Paulo', shortText: 'São Paulo', types: %w[administrative_area_level_2 political] },
      { longText: 'São Paulo', shortText: 'SP', types: %w[administrative_area_level_1 political] },
      { longText: 'Brasil', shortText: 'BR', types: %w[country political] }
    ]
  end
  let(:place) do
    {
      id: 'places/abc123',
      displayName: { text: 'Alpha Restaurante' },
      formattedAddress: 'Rua das Flores, 123 - Pinheiros, São Paulo - SP, 05422-000, Brasil',
      addressComponents: address_components,
      googleMapsUri: 'https://maps.google.com/?cid=123',
      internationalPhoneNumber: '+55 11 99999-8888',
      websiteUri: 'https://alpha.example.com',
      location: { latitude: -23.55, longitude: -46.63 },
      rating: 4.7,
      userRatingCount: 231,
      types: ['restaurant'],
      photos: [{ name: 'places/abc123/photos/1' }, { name: 'places/abc123/photos/2' }],
      currentOpeningHours: { openNow: false },
      regularOpeningHours: { weekdayDescriptions: ['segunda-feira: 11:00 – 23:00'] }
    }
  end

  def stub_places(places)
    stub_request(:post, described_class::ENDPOINT)
      .to_return(status: 200, body: { places: places }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  def search(country: nil, **extra)
    params = { query: 'restaurante', location: 'Sao Paulo', radius: 5000, limit: 1, api_key: 'test-key' }
    params[:country] = country if country
    described_class.new(**params, **extra).search
  end

  it 'maps Google Places text search results to prospecting lead attributes' do
    stub_places([place])

    expect(search.first).to include(
      provider: 'google_places',
      provider_place_id: 'places/abc123',
      name: 'Alpha Restaurante',
      phone: '+55 11 99999-8888',
      website: 'https://alpha.example.com',
      category: 'restaurant'
    )
  end

  # Endereço, país e sinais do lugar (#677, E1 frente C): tudo vem de campos estruturados do Google.
  describe 'endereço estruturado e sinais do lugar' do
    it 'tira bairro, cidade, estado e país de addressComponents e guarda o link do Maps' do
      stub_places([place])

      expect(search.first).to include(
        neighborhood: 'Pinheiros', city: 'São Paulo', state: 'SP', country: 'BR',
        google_maps_uri: 'https://maps.google.com/?cid=123'
      )
    end

    it 'usa o município (administrative_area_level_2) quando o Google não manda locality' do
      components = address_components.reject { |component| component[:types].include?('locality') }
      stub_places([place.merge(addressComponents: components)])

      expect(search.first[:city]).to eq('São Paulo')
    end

    it 'não lê cidade nem estado do texto do endereço e cai para o país da busca sem addressComponents' do
      stub_places([place.except(:addressComponents)])

      expect(search(country: 'PT').first).to include(neighborhood: nil, city: nil, state: nil, country: 'PT')
    end

    it 'deriva fotos e horário do payload do Google' do
      stub_places([place])

      expect(search.first).to include(has_photos: true, photo_count: 2, open_now: false, has_opening_hours: true)
    end

    it 'deixa open_now nil quando o Google não diz se está aberto e marca sem fotos e sem horário' do
      stub_places([place.except(:photos, :currentOpeningHours, :regularOpeningHours)])

      expect(search.first).to include(has_photos: false, photo_count: 0, open_now: nil, has_opening_hours: false)
    end

    it 'pede addressComponents e googleMapsUri no FieldMask' do
      stub_places([place])

      search

      expect(
        a_request(:post, described_class::ENDPOINT).with do |request|
          request.headers['X-Goog-Fieldmask'].split(',').to_set >= Set['places.addressComponents', 'places.googleMapsUri']
        end
      ).to have_been_made
    end
  end

  describe 'país da busca' do
    it 'manda regionCode e languageCode do país da conta' do
      stub_places([place])

      search(country: 'PT')

      expect(
        a_request(:post, described_class::ENDPOINT).with do |request|
          JSON.parse(request.body).slice('regionCode', 'languageCode') == { 'regionCode' => 'PT', 'languageCode' => 'pt-PT' }
        end
      ).to have_been_made
    end

    it 'usa o Brasil quando o país não vem' do
      stub_places([place])

      search

      expect(
        a_request(:post, described_class::ENDPOINT).with do |request|
          JSON.parse(request.body).slice('regionCode', 'languageCode') == { 'regionCode' => 'BR', 'languageCode' => 'pt-BR' }
        end
      ).to have_been_made
    end
  end

  # A chave é da plataforma (#683): o texto do Google fala do nosso projeto no Google Cloud e não chega ao cliente.
  # Cada status do Google vira uma frase nossa em português (#677).
  describe 'erro do Google' do
    let(:provider) do
      described_class.new(query: 'restaurante', location: 'Sao Paulo', radius: 5000, limit: 1, api_key: 'chave', account_id: 42)
    end
    let(:service_disabled) do
      'Places API (New) has not been used in project 123456789 before or it is disabled. Enable it by visiting ' \
        'https://console.developers.google.com/apis/api/places.googleapis.com/overview?project=123456789'
    end
    let(:indisponivel) { 'A busca no Google está indisponível no momento. Fale com o suporte.' }
    let(:sobrecarregado) { 'A busca no Google está sobrecarregada agora. Tente de novo em alguns minutos.' }
    let(:parametros) { 'O Google recusou os dados da busca. Confira o termo, o local e a área e tente de novo.' }
    let(:sem_resposta) { 'O Google não respondeu a tempo. Tente de novo em alguns minutos.' }

    def stub_google_error(status, message, google_status: nil, reason: nil)
      error = { code: status, message: message, status: google_status }.compact
      error[:details] = [{ '@type': 'type.googleapis.com/google.rpc.ErrorInfo', reason: reason }] if reason
      stub_request(:post, described_class::ENDPOINT).to_return(status: status, body: { error: error }.to_json)
    end

    it 'devolve texto nosso no 403 e registra a mensagem do Google só no log do servidor' do
      stub_google_error(403, service_disabled, google_status: 'PERMISSION_DENIED')
      allow(Rails.logger).to receive(:warn)

      expect { provider.search }.to raise_error(Autonomia::Prospecting::SearchRunner::ProviderError) { |error|
        expect(error.message).to eq(indisponivel)
        expect(error.message).not_to include('project')
      }
      expect(Rails.logger).to have_received(:warn)
        .with(a_string_including('account_id=42', 'status=403', 'google_status=PERMISSION_DENIED', 'project 123456789'))
    end

    it 'diferencia cota estourada (RESOURCE_EXHAUSTED) de indisponível' do
      stub_google_error(429, 'Quota exceeded for quota metric', google_status: 'RESOURCE_EXHAUSTED')

      expect { provider.search }.to raise_error(Autonomia::Prospecting::SearchRunner::ProviderError, sobrecarregado)
    end

    it 'diz que os dados da busca foram recusados em INVALID_ARGUMENT' do
      stub_google_error(400, 'Invalid circle radius', google_status: 'INVALID_ARGUMENT')

      expect { provider.search }.to raise_error(Autonomia::Prospecting::SearchRunner::ProviderError, parametros)
    end

    it 'não culpa a busca quando o INVALID_ARGUMENT é chave vencida' do
      stub_google_error(400, 'API key expired. Please renew the API key.', google_status: 'INVALID_ARGUMENT', reason: 'API_KEY_INVALID')

      expect { provider.search }.to raise_error(Autonomia::Prospecting::SearchRunner::ProviderError, indisponivel)
    end

    it 'pede para tentar de novo em UNAVAILABLE' do
      stub_google_error(503, 'The service is currently unavailable.', google_status: 'UNAVAILABLE')

      expect { provider.search }.to raise_error(Autonomia::Prospecting::SearchRunner::ProviderError, sem_resposta)
    end

    it 'usa o código HTTP quando o Google não manda status' do
      stub_google_error(429, 'Quota exceeded')

      expect { provider.search }.to raise_error(Autonomia::Prospecting::SearchRunner::ProviderError, sobrecarregado)
    end

    it 'traduz a falta de resposta do Google em vez de repassar a exceção de rede' do
      stub_request(:post, described_class::ENDPOINT).to_timeout

      expect { provider.search }.to raise_error(Autonomia::Prospecting::SearchRunner::ProviderError, sem_resposta)
    end

    it 'traduz resposta que não é JSON' do
      stub_request(:post, described_class::ENDPOINT).to_return(status: 200, body: '<html>erro</html>')

      expect { provider.search }.to raise_error(Autonomia::Prospecting::SearchRunner::ProviderError, indisponivel)
    end

    it 'responde em português também para conta com locale pt_BR' do
      stub_google_error(403, service_disabled, google_status: 'PERMISSION_DENIED')

      I18n.with_locale(:pt_BR) do
        expect { provider.search }.to raise_error(Autonomia::Prospecting::SearchRunner::ProviderError, indisponivel)
      end
    end
  end
end
