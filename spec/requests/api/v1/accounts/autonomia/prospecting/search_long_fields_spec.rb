require 'rails_helper'

# #723: um lugar do Google com site ou link do Maps maior que a coluna (255, ApplicationRecord#validates_column_content_length)
# derrubava a busca inteira, com o Google já pago. Caso real: busca 20 da conta 1 da autonomia, 25/09.
RSpec.describe 'Autonomia prospecting search with long place fields', type: :request do
  around { |example| with_modified_env('GOOGLE_PLACES_API_KEY' => 'chave-da-plataforma') { example.run } }

  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:searches_path) { "/api/v1/accounts/#{account.id}/autonomia/prospecting/searches" }
  let(:tracking) { "?utm_source=google&utm_medium=organic&utm_campaign=#{'x' * 260}" }
  let(:long_maps_uri) { "https://maps.google.com/?cid=1&#{tracking.delete_prefix('?')}" }
  let(:places) do
    [
      { id: 'places/longo', displayName: { text: 'Clinica Longa' }, formattedAddress: 'Florianopolis, SC',
        websiteUri: "https://clinica.example.com/agendamento#{tracking}", googleMapsUri: long_maps_uri },
      { id: 'places/normal', displayName: { text: 'Clinica Normal' }, formattedAddress: 'Florianopolis, SC',
        websiteUri: 'https://normal.example.com/?ref=gmb', googleMapsUri: 'https://maps.google.com/?cid=2' },
      { id: 'places/sem-saida', displayName: { text: 'Clinica Sem Saida' }, formattedAddress: 'Florianopolis, SC',
        websiteUri: "https://sem-saida.example.com/#{'a' * 300}" }
    ]
  end

  before do
    Autonomia::Prospecting::Config.enable_for!(account)
    Autonomia::Prospecting::Setting.for_account(account).update!(provider: 'google_places', cache_ttl_seconds: 0)
    stub_request(:post, Autonomia::Prospecting::Providers::GooglePlacesProvider::ENDPOINT)
      .to_return(status: 200, body: { places: places }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  def run_search
    post searches_path, params: { search: { query: 'clinica', location: 'Florianopolis, SC', radius: 5000, requested_limit: 3 } },
                        headers: auth_headers(admin), as: :json
  end

  it 'termina a busca com todos os lugares quando um deles tem site e link do Maps longos' do
    run_search

    expect(response).to have_http_status(:created)
    expect(Autonomia::Prospecting::Search.last.status).to eq('completed')
    expect(Autonomia::Prospecting::Lead.where(account: account).count).to eq(3)
  end

  it 'tira o rastreio da URL longa e guarda o endereço que cabe' do
    run_search

    lead = Autonomia::Prospecting::Lead.find_by(account: account, provider_place_id: 'places/longo')
    expect(lead.website).to eq('https://clinica.example.com/agendamento')
    expect(lead.google_maps_uri).to eq('https://maps.google.com/?cid=1')
  end

  it 'deixa vazio o site que não cabe nem sem rastreio, sem perder o lead' do
    run_search

    expect(Autonomia::Prospecting::Lead.find_by(account: account, provider_place_id: 'places/sem-saida').website).to be_nil
  end

  it 'não mexe no site que já cabe, mesmo com parâmetro' do
    run_search

    expect(Autonomia::Prospecting::Lead.find_by(account: account, provider_place_id: 'places/normal').website)
      .to eq('https://normal.example.com/?ref=gmb')
  end
end
