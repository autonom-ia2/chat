require 'rails_helper'

# O card do lead (#678, E2 frente E) mostra bairro, quantidade de fotos e o link do lugar no Maps. O provider grava os
# três em colunas desde a E1; lead gravado antes delas usa o que o Google devolveu no raw_payload, sem migração.
RSpec.describe 'Autonomia prospecting lead card payload', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:base_path) { "/api/v1/accounts/#{account.id}/autonomia/prospecting" }
  let(:photos) { Array.new(7) { |index| { 'name' => "places/x/photos/#{index}" } } }
  let!(:new_lead) do
    Autonomia::Prospecting::Lead.create!(
      account: account, provider: 'google_places', provider_place_id: 'place-new', name: 'Padaria Nova',
      neighborhood: 'Batel', photo_count: 12, has_photos: true, google_maps_uri: 'https://maps.google.com/?cid=1',
      raw_payload: { 'photos' => photos, 'googleMapsUri' => 'https://maps.google.com/?cid=antigo' }
    )
  end
  let!(:old_lead) do
    Autonomia::Prospecting::Lead.create!(
      account: account, provider: 'google_places', provider_place_id: 'place-old', name: 'Padaria Antiga',
      raw_payload: { 'photos' => photos, 'googleMapsUri' => 'https://maps.google.com/?cid=2' }
    )
  end
  let!(:bare_lead) do
    Autonomia::Prospecting::Lead.create!(
      account: account, provider: 'mock', provider_place_id: 'place-bare', name: 'Padaria Sem Fotos', raw_payload: {}
    )
  end

  before { Autonomia::Prospecting::Config.enable_for!(account) }

  def card_fields(leads, name)
    leads.find { |lead| lead['name'] == name }.slice('neighborhood', 'photo_count', 'google_maps_uri')
  end

  def expect_card_fields(leads)
    expect(card_fields(leads, 'Padaria Nova')).to eq(
      'neighborhood' => 'Batel', 'photo_count' => 12, 'google_maps_uri' => 'https://maps.google.com/?cid=1'
    )
    expect(card_fields(leads, 'Padaria Antiga')).to eq(
      'neighborhood' => nil, 'photo_count' => 7, 'google_maps_uri' => 'https://maps.google.com/?cid=2'
    )
    expect(card_fields(leads, 'Padaria Sem Fotos')).to eq(
      'neighborhood' => nil, 'photo_count' => 0, 'google_maps_uri' => nil
    )
  end

  it 'a busca aberta entrega bairro, fotos e link do Maps de cada lead' do
    search = Autonomia::Prospecting::Search.create!(
      account: account, query: 'padaria', metadata: { 'lead_ids' => [new_lead.id, old_lead.id, bare_lead.id] }
    )

    get "#{base_path}/searches/#{search.id}", headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    expect_card_fields(response.parsed_body.dig('payload', 'leads'))
  end

  it 'a lista de leads entrega os mesmos campos' do
    get "#{base_path}/leads", headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    expect_card_fields(response.parsed_body['payload'])
  end
end
