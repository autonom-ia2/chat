require 'rails_helper'

# Frente de modo e jogadas (#677): a jogada e o tipo de decisor vão no pedido,
# ficam no metadata da busca e voltam no payload (criar, abrir e histórico).
RSpec.describe 'Autonomia prospecting search mode metadata', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:searches_path) { "/api/v1/accounts/#{account.id}/autonomia/prospecting/searches" }

  before do
    Autonomia::Prospecting::Config.enable_for!(account)
    Autonomia::Prospecting::Setting.for_account(account).update!(provider: 'mock')
  end

  def create_search(metadata)
    post searches_path,
         params: { search: { query: 'padaria', location: 'Curitiba, PR', requested_limit: 1, metadata: metadata } },
         headers: auth_headers(admin),
         as: :json
  end

  it 'grava a jogada e o tipo de decisor e devolve nos três payloads' do
    create_search(score_mode: 'gbp', preset_id: 'vender-site', decision_maker_type: 'manager')

    expect(response).to have_http_status(:created)
    created = response.parsed_body.dig('payload', 'search')
    expect(created).to include('preset_id' => 'vender-site', 'decision_maker_type' => 'manager', 'score_mode' => 'gbp')

    search = account.autonomia_prospecting_searches.last
    expect(search.metadata).to include('preset_id' => 'vender-site', 'decision_maker_type' => 'manager')

    get "#{searches_path}/#{search.id}", headers: auth_headers(admin)
    expect(response.parsed_body['payload']).to include('preset_id' => 'vender-site', 'decision_maker_type' => 'manager')

    get searches_path, headers: auth_headers(admin)
    expect(response.parsed_body['payload'].first).to include('preset_id' => 'vender-site')
  end

  it 'sem jogada grava preset_id nulo e decisor proprietário' do
    create_search(score_mode: 'general')

    expect(response).to have_http_status(:created)
    created = response.parsed_body.dig('payload', 'search')
    expect(created['preset_id']).to be_nil
    expect(created['decision_maker_type']).to eq('owner')
    expect(account.autonomia_prospecting_searches.last.metadata['decision_maker_type']).to eq('owner')
  end

  it 'busca antiga, sem os campos no metadata, devolve os padrões' do
    search = Autonomia::Prospecting::Search.create!(account: account, user: admin, query: 'bar', requested_limit: 1)

    get "#{searches_path}/#{search.id}", headers: auth_headers(admin)

    expect(response.parsed_body['payload']).to include('preset_id' => nil, 'decision_maker_type' => 'owner')
  end

  it 'recusa jogada que não existe com mensagem em português' do
    create_search(score_mode: 'gbp', preset_id: 'jogada-inventada')

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq(I18n.t('autonomia.prospecting.presets.invalid'))
    expect(account.autonomia_prospecting_searches.count).to eq(0)
  end

  it 'recusa jogada de outro modo' do
    create_search(score_mode: 'general', preset_id: 'vender-site')

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq(I18n.t('autonomia.prospecting.presets.invalid'))
  end
end
