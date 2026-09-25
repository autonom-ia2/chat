require 'rails_helper'

# A virada para a nota do Orth é do superadmin (#681): a conta não troca o motor pela API de configurações.
RSpec.describe 'Autonomia prospecting settings score engine', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:settings_url) { "/api/v1/accounts/#{account.id}/autonomia/prospecting/settings" }

  before { Autonomia::Prospecting::Config.enable_for!(account) }

  it 'ignora o motor enviado pela conta, solto ou dentro do metadata' do
    patch settings_url, params: { settings: { score_engine: 'orth', metadata: { score_engine: 'orth' }, cache_ttl_seconds: 600 } },
                        headers: auth_headers(admin), as: :json

    expect(response).to have_http_status(:ok)
    setting = Autonomia::Prospecting::Setting.for_account(account)
    expect(setting.cache_ttl_seconds).to eq(600)
    expect(setting.score_engine).to eq('legacy')
  end

  # Conta virada com a nota do Orth fora do ar: a busca não mostra a legada no lugar dela, e a tela recebe a frase.
  it 'recusa a busca em português quando a conta está no Orth e a nota do Orth falha' do
    Autonomia::Prospecting::Setting.for_account(account).update!(score_engine: 'orth', provider: 'mock')
    allow(Autonomia::Prospecting::Scoring::OrthScorer).to receive(:new).and_raise(RuntimeError, 'fórmula fora do ar')

    post "/api/v1/accounts/#{account.id}/autonomia/prospecting/searches",
         params: { search: { query: 'padaria', location: 'Curitiba, PR', requested_limit: 2 } }, headers: auth_headers(admin), as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('A nota da busca está indisponível no momento. Fale com o suporte.')
    expect(account.autonomia_prospecting_searches.last).to be_failed
  end

  it 'não desvira a conta que o superadmin virou' do
    Autonomia::Prospecting::Setting.for_account(account).update!(score_engine: 'orth')

    patch settings_url, params: { settings: { score_engine: 'legacy', search_score_mode: 'general' } }, headers: auth_headers(admin), as: :json

    expect(response).to have_http_status(:ok)
    expect(Autonomia::Prospecting::Setting.for_account(account).score_engine).to eq('orth')
  end
end
