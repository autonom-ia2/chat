require 'rails_helper'

# Busca que não pode trazer nada é recusada antes de chamar o Google (#677): sem busca gravada, sem cache e com a
# frase em português que a tela mostra.
RSpec.describe 'Autonomia prospecting search refusals', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:google_endpoint) { Autonomia::Prospecting::Providers::GooglePlacesProvider::ENDPOINT }

  before do
    Autonomia::Prospecting::Config.enable_for!(account)
    Autonomia::Prospecting::Setting.for_account(account).update!(provider: 'google_places')
  end

  def create_search(requested_limit:, advanced_filters: {}, filters: {})
    post "/api/v1/accounts/#{account.id}/autonomia/prospecting/searches",
         params: {
           search: {
             query: 'padaria', location: 'Curitiba, PR', requested_limit: requested_limit,
             metadata: { advanced_filters: advanced_filters, filters: filters }
           }
         },
         headers: { 'api_access_token' => admin.access_token.token },
         as: :json
  end

  def google_places(count)
    places = Array.new(count) do |index|
      { id: "places/p#{index}", displayName: { text: "Padaria #{index + 1}" }, formattedAddress: 'Curitiba, PR' }
    end
    { status: 200, body: { places: places }.to_json, headers: { 'Content-Type' => 'application/json' } }
  end

  describe 'faixa de posição que o Google não alcança' do
    around { |example| with_modified_env('GOOGLE_PLACES_API_KEY' => 'chave-da-plataforma') { example.run } }

    it 'recusa começar a faixa depois da Quantidade, sem chamar o Google nem gravar busca' do
      stub_request(:post, google_endpoint).to_return(google_places(10))

      create_search(requested_limit: 10, advanced_filters: { outside_top: 10 })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(
        'O Google traz até 10 posições nesta busca. Comece a faixa de posição em até 10 ou aumente a quantidade.'
      )
      expect(a_request(:post, google_endpoint)).not_to have_been_made
      expect(account.autonomia_prospecting_searches.count).to eq(0)
    end

    it 'recusa começar depois da 20ª mesmo com Quantidade 60 e Expandir raio, sem gastar as 3 chamadas' do
      stub_request(:post, google_endpoint).to_return(google_places(20))

      create_search(requested_limit: 60, advanced_filters: { outside_top: 20 }, filters: { auto_expand_radius: true })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('até 20 posições')
      expect(a_request(:post, google_endpoint)).not_to have_been_made
      expect(account.autonomia_prospecting_searches.count).to eq(0)
    end

    it 'aceita a faixa que ainda cabe no que o Google devolve' do
      stub_request(:post, google_endpoint).to_return(google_places(10))

      create_search(requested_limit: 10, advanced_filters: { outside_top: 9 })

      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig('payload', 'leads').map { |lead| lead['name'] }).to eq(['Padaria 10'])
    end
  end

  it 'avisa em português quando a chave da plataforma do Google não está configurada' do
    with_modified_env('GOOGLE_PLACES_API_KEY' => nil) do
      allow(Rails.logger).to receive(:warn)

      create_search(requested_limit: 10)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('A busca no Google está indisponível no momento. Fale com o suporte.')
      expect(Rails.logger).to have_received(:warn).with(a_string_including('GOOGLE_PLACES_API_KEY'))
    end
  end
end
