require 'rails_helper'

# Prova dos filtros de foto, aberto agora e tem horário com uma resposta REAL do Google Places (#677).
# Gravada em 24/09/2026 na Places API (New) searchText, "borracharia em Diadema, SP", com o FieldMask do provider.
# Da gravação saíram só dados de pessoas: autor e texto das avaliações e autor das fotos.
# Contagens da própria resposta: 20 lugares; 12 com photos e 8 sem; 14 com currentOpeningHours.openNow = true;
# 15 com regularOpeningHours e 5 sem.
RSpec.describe Autonomia::Prospecting::SearchRunner do
  around { |example| with_modified_env('GOOGLE_PLACES_API_KEY' => 'chave-da-plataforma') { example.run } }

  let(:account) { create(:account) }
  let(:user) { create(:user, :administrator, account: account) }
  let(:fixture) { JSON.parse(file_fixture('google_places/search_text_real_borracharia_diadema.json').read) }

  before do
    Autonomia::Prospecting::Setting.for_account(account).update!(provider: 'google_places')
    stub_request(:post, Autonomia::Prospecting::Providers::GooglePlacesProvider::ENDPOINT)
      .to_return(status: 200, body: fixture.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  def place_ids_with(advanced_filters)
    described_class.new(
      account: account,
      user: user,
      params: { query: 'borracharia', location: 'Diadema, SP', requested_limit: 20, advanced_filters: advanced_filters }
    ).perform.leads.map(&:provider_place_id)
  end

  def expected_ids(&)
    fixture['places'].select(&).pluck('id')
  end

  it 'sem filtro guarda os 20 lugares' do
    expect(place_ids_with({}).size).to eq(20)
  end

  it 'com foto: sim mantém exatamente os 12 que têm photos' do
    expect(place_ids_with(has_photos: 'yes')).to match_array(expected_ids { |place| place['photos'].present? })
    expect(place_ids_with(has_photos: 'yes').size).to eq(12)
  end

  it 'com foto: não mantém exatamente os 8 sem photos' do
    expect(place_ids_with(has_photos: 'no')).to match_array(expected_ids { |place| place['photos'].blank? })
    expect(place_ids_with(has_photos: 'no').size).to eq(8)
  end

  it 'aberto agora: sim mantém exatamente os 14 com openNow true' do
    expect(place_ids_with(open_now: 'yes')).to match_array(expected_ids { |place| place.dig('currentOpeningHours', 'openNow') == true })
    expect(place_ids_with(open_now: 'yes').size).to eq(14)
  end

  it 'tem horário: sim mantém exatamente os 15 com regularOpeningHours' do
    expect(place_ids_with(has_opening_hours: 'yes')).to match_array(expected_ids { |place| place['regularOpeningHours'].present? })
    expect(place_ids_with(has_opening_hours: 'yes').size).to eq(15)
  end
end
