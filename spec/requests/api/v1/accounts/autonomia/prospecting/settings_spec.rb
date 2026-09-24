require 'rails_helper'

RSpec.describe 'Autonomia prospecting settings API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:settings_url) { "/api/v1/accounts/#{account.id}/autonomia/prospecting/settings" }

  before do
    Autonomia::Prospecting::Config.enable_for!(account)
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
  end

  it 'ignores keys, provider, limits and enrichment_enabled sent by the account' do
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    setting = Autonomia::Prospecting::Setting.for_account(account)

    patch settings_url,
          params: {
            settings: {
              provider: 'mock',
              provider_enabled: true,
              default_limit: 10,
              max_results_per_search: 10,
              daily_limit: 3,
              monthly_limit: 10,
              enrichment_enabled: true,
              google_places_api_key: 'chave-da-conta',
              google_maps_browser_api_key: 'chave-de-navegador-da-conta',
              cache_ttl_seconds: 600,
              default_crm_pipeline_id: pipeline.id,
              default_crm_stage_id: stage.id
            }
          },
          headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    setting.reload
    expect(
      provider: setting.provider, provider_enabled: setting.provider_enabled, default_limit: setting.default_limit,
      max_results_per_search: setting.max_results_per_search, daily_limit: setting.daily_limit, monthly_limit: setting.monthly_limit,
      enrichment_enabled: setting.enrichment_enabled, google_places_api_key: setting.read_attribute(:google_places_api_key),
      google_maps_browser_api_key: setting.read_attribute(:google_maps_browser_api_key)
    ).to eq(
      provider: 'google_places', provider_enabled: false, default_limit: 20, max_results_per_search: 20, daily_limit: nil,
      monthly_limit: nil, enrichment_enabled: false, google_places_api_key: nil, google_maps_browser_api_key: nil
    )
    expect(setting.slice(:cache_ttl_seconds, :default_crm_pipeline_id, :default_crm_stage_id))
      .to eq('cache_ttl_seconds' => 600, 'default_crm_pipeline_id' => pipeline.id, 'default_crm_stage_id' => stage.id)
    expect(Autonomia::Prospecting::Config.research_enabled?(account.reload)).to be(false)
  end

  it 'returns the platform state read-only, without the server Places key' do
    with_modified_env('GOOGLE_PLACES_API_KEY' => 'chave-de-servidor', 'GOOGLE_MAPS_BROWSER_API_KEY' => 'chave-de-navegador') do
      Autonomia::Prospecting::Config.enable_research_for!(account)
      create(:integrations_hook, account: account, app_id: 'crm_kanban_ai', hook_type: :account, settings: { 'api_key' => 'chave-ia' })

      get settings_url, headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      payload = response.parsed_body['payload']
      expect(payload.slice('platform_google_places_configured', 'google_maps_browser_api_key', 'research_enabled', 'ai_credential_configured'))
        .to eq('platform_google_places_configured' => true, 'google_maps_browser_api_key' => 'chave-de-navegador',
               'research_enabled' => true, 'ai_credential_configured' => true)
      expect(response.body).not_to include('chave-de-servidor')
      expect(response.body).not_to include('chave-ia')
      expect(payload.keys).not_to include('provider', 'provider_enabled', 'max_results_per_search', 'daily_limit', 'monthly_limit',
                                          'enrichment_enabled', 'google_places_api_key', 'has_google_places_api_key')
    end
  end

  it 'reports missing platform keys and missing Kanban AI credential even with the system key' do
    with_modified_env('GOOGLE_PLACES_API_KEY' => nil, 'GOOGLE_MAPS_BROWSER_API_KEY' => nil) do
      InstallationConfig.where(name: 'CAPTAIN_OPEN_AI_API_KEY').first_or_create!(value: 'chave-do-sistema')
      Autonomia::Prospecting::Setting.for_account(account).update!(google_places_api_key: 'chave-antiga-da-conta')

      get settings_url, headers: auth_headers(admin)

      payload = response.parsed_body['payload']
      expect(payload['platform_google_places_configured']).to be(false)
      expect(payload['google_maps_browser_api_key']).to be_nil
      expect(payload['research_enabled']).to be(false)
      expect(payload['ai_credential_configured']).to be(false)
    end
  end

  # As chaves da plataforma vêm só do ambiente (#683). Uma InstallationConfig homônima apareceria no superadmin,
  # então não pode valer como chave.
  it 'does not read platform keys from an InstallationConfig with the same name' do
    with_modified_env('GOOGLE_PLACES_API_KEY' => nil, 'GOOGLE_MAPS_BROWSER_API_KEY' => nil) do
      InstallationConfig.where(name: 'GOOGLE_PLACES_API_KEY').first_or_create!(value: 'chave-de-servidor-no-banco')
      InstallationConfig.where(name: 'GOOGLE_MAPS_BROWSER_API_KEY').first_or_create!(value: 'chave-de-navegador-no-banco')

      get settings_url, headers: auth_headers(admin)

      payload = response.parsed_body['payload']
      expect(payload['platform_google_places_configured']).to be(false)
      expect(payload['google_maps_browser_api_key']).to be_nil
      expect(response.body).not_to include('no-banco')
    end
  end

  # Conta cuja linha nasceu em mock antes da E0 recebe lead fictício mesmo com a chave da plataforma pronta. A tela
  # precisa saber disso para não mostrar o selo de chaves prontas (#683).
  it 'reports the mock provider read-only, so the screen does not claim the platform keys are in use' do
    with_modified_env('GOOGLE_PLACES_API_KEY' => 'chave-de-servidor') do
      Autonomia::Prospecting::Setting.for_account(account).update!(provider: 'mock')

      get settings_url, headers: auth_headers(admin)
      mock_payload = response.parsed_body['payload']
      Autonomia::Prospecting::Setting.for_account(account).update!(provider: 'google_places')
      get settings_url, headers: auth_headers(admin)
      google_payload = response.parsed_body['payload']

      expect(mock_payload.slice('platform_google_places_configured', 'mock_provider'))
        .to eq('platform_google_places_configured' => true, 'mock_provider' => true)
      expect(google_payload['mock_provider']).to be(false)
    end
  end

  # País da busca por conta (#677, E1 frente C): Brasil por padrão, lista de países do Orth.
  describe 'search_country' do
    it 'devolve Brasil e a lista de países quando a conta nunca escolheu' do
      get settings_url, headers: auth_headers(admin)

      payload = response.parsed_body['payload']
      expect(payload['search_country']).to eq('BR')
      expect(payload['search_countries']).to eq(Autonomia::Prospecting::SearchCountry::ALLOWED)
    end

    it 'aceita o país no PUT, com a mesma permissão dos outros campos' do
      patch settings_url, params: { settings: { search_country: 'pt' } }, headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('payload', 'search_country')).to eq('PT')
      expect(Autonomia::Prospecting::Setting.for_account(account).search_country).to eq('PT')
    end

    it 'recusa país fora da lista com mensagem em português' do
      patch settings_url, params: { settings: { search_country: 'ZZ' } }, headers: auth_headers(admin)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('Escolha um país da lista.')
      expect(Autonomia::Prospecting::Setting.for_account(account).search_country).to eq('BR')
    end

    it 'mantém o país quando o PUT não fala dele' do
      Autonomia::Prospecting::Setting.for_account(account).update!(search_country: 'MX')

      patch settings_url, params: { settings: { cache_ttl_seconds: 600 } }, headers: auth_headers(admin)

      expect(response.parsed_body.dig('payload', 'search_country')).to eq('MX')
    end

    it 'não deixa agente sem permissão trocar o país' do
      agent = create(:user, account: account, role: :agent)

      patch settings_url, params: { settings: { search_country: 'PT' } }, headers: auth_headers(agent)

      expect(response).to have_http_status(:unauthorized)
      expect(Autonomia::Prospecting::Setting.for_account(account).search_country).to eq('BR')
    end
  end

  def auth_headers(user)
    { 'api_access_token' => user.access_token.token }
  end
end
