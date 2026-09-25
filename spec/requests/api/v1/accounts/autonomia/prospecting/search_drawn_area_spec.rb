require 'rails_helper'

# Área desenhada pela API (#678, E2 frente B): os pontos do polígono passam pelo filtro de parâmetros e voltam no
# payload da busca.
RSpec.describe 'Autonomia prospecting drawn search area', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:searches_path) { "/api/v1/accounts/#{account.id}/autonomia/prospecting/searches" }
  let(:path) do
    [{ lat: -25.50, lng: -49.30 }, { lat: -25.50, lng: -49.20 }, { lat: -25.40, lng: -49.25 }]
  end

  before do
    Autonomia::Prospecting::Config.enable_for!(account)
    Autonomia::Prospecting::Setting.for_account(account).update!(provider: 'mock')
  end

  it 'grava o polígono enviado e devolve tipo e pontos no payload' do
    post searches_path,
         params: { search: { query: 'padaria', location: 'Curitiba, PR', requested_limit: 3, area_type: 'polygon',
                             area_config: { path: path } } },
         headers: auth_headers(admin),
         as: :json

    expect(response).to have_http_status(:created)
    created = response.parsed_body.dig('payload', 'search')
    expect(created['area_type']).to eq('polygon')
    expect(created.dig('area_config', 'path')).to eq(path.map { |point| point.transform_keys(&:to_s) })
  end

  it 'recusa área desenhada vazia com a frase em português' do
    post searches_path,
         params: { search: { query: 'padaria', location: 'Curitiba, PR', requested_limit: 3, area_type: 'rectangle',
                             area_config: {} } },
         headers: auth_headers(admin),
         as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to include(I18n.t('autonomia.prospecting.errors.drawn_area_required'))
  end
end
