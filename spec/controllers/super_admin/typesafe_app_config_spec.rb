require 'rails_helper'

RSpec.describe 'Super Admin TypeSafe AI configuration', type: :request do
  let(:super_admin) { create(:super_admin) }

  before do
    sign_in(super_admin, scope: :super_admin)
  end

  it 'shows TypeSafe AI in the SuperAdmin settings card and navigation' do
    get '/super_admin/settings'

    expect(response).to have_http_status(:success)
    expect(response.body.scan('TypeSafe AI').length).to be >= 2
    expect(response.body).to include('/super_admin/app_config?config=typesafe')
  end

  it 'renders TypeSafe beside the existing settings without returning a saved API key' do
    enable_test_encryption!
    AiProviderCredential.create!(provider: 'typesafe', api_key: 'ts_should_never_be_rendered')

    get '/super_admin/app_config?config=typesafe'

    expect(response).to have_http_status(:success)
    expect(response.body).to include('TypeSafe API Key')
    expect(response.body).to include('jev-1.13.0')
    expect(response.body).to include('Credential configured. The saved key is never returned to this page.')
    expect(response.body).not_to include('ts_should_never_be_rendered')
    expect(response.body).not_to include('data-target="app_config_TYPESAFE_API_KEY"')
  end

  it 'stores the API key encrypted and persists only non-secret settings in InstallationConfig' do
    enable_test_encryption!

    post '/super_admin/app_config?config=typesafe', params: {
      app_config: {
        TYPESAFE_JEV_ENABLED: 'true',
        TYPESAFE_JEV_MODEL: 'jev-1.13.0',
        TYPESAFE_API_KEY: 'ts_secret_from_form'
      }
    }

    expect(response).to redirect_to(super_admin_settings_path)
    credential = AiProviderCredential.find_by!(provider: 'typesafe')
    raw = AiProviderCredential.connection.select_value(
      "SELECT api_key FROM ai_provider_credentials WHERE id = #{credential.id.to_i}"
    )
    expect(raw).not_to include('ts_secret_from_form')
    expect(credential.api_key).to eq('ts_secret_from_form')
    expect(InstallationConfig.find_by(name: 'TYPESAFE_API_KEY')&.value).to be_nil
    expect(GlobalConfig.get('TYPESAFE_JEV_ENABLED')['TYPESAFE_JEV_ENABLED']).to be(true)
    expect(GlobalConfig.get('TYPESAFE_JEV_MODEL')['TYPESAFE_JEV_MODEL']).to eq('jev-1.13.0')
  end

  it 'keeps the existing API key when the write-only field is submitted blank' do
    enable_test_encryption!
    credential = AiProviderCredential.create!(provider: 'typesafe', api_key: 'ts_existing')

    post '/super_admin/app_config?config=typesafe', params: {
      app_config: {
        TYPESAFE_JEV_ENABLED: 'false',
        TYPESAFE_JEV_MODEL: 'jev-1.13.0',
        TYPESAFE_API_KEY: ''
      }
    }

    expect(response).to redirect_to(super_admin_settings_path)
    expect(credential.reload.api_key).to eq('ts_existing')
  end

  it 'refuses to store or enable TypeSafe without the encryption vault' do
    allow(Chatwoot).to receive(:encryption_configured?).and_return(false)

    expect do
      post '/super_admin/app_config?config=typesafe', params: {
        app_config: {
          TYPESAFE_JEV_ENABLED: 'true',
          TYPESAFE_JEV_MODEL: 'jev-1.13.0',
          TYPESAFE_API_KEY: 'ts_plaintext_must_not_persist'
        }
      }
    end.not_to change(AiProviderCredential, :count)

    expect(response).to redirect_to(super_admin_app_config_path(config: 'typesafe'))
    expect(flash[:alert]).to include('ACTIVE_RECORD_ENCRYPTION')
    expect(GlobalConfig.get('TYPESAFE_JEV_ENABLED')['TYPESAFE_JEV_ENABLED']).not_to eq('true')
  end

  it 'rejects enabling Jev until a TypeSafe credential exists' do
    enable_test_encryption!

    post '/super_admin/app_config?config=typesafe', params: {
      app_config: { TYPESAFE_JEV_ENABLED: 'true', TYPESAFE_JEV_MODEL: 'jev-1.13.0', TYPESAFE_API_KEY: '' }
    }

    expect(response).to redirect_to(super_admin_app_config_path(config: 'typesafe'))
    expect(flash[:alert]).to include('Configure the TypeSafe API key first.')
  end

  it 'tests the saved credential through the real TypeSafe HTTP client contract' do
    enable_test_encryption!
    AiProviderCredential.create!(provider: 'typesafe', api_key: 'ts_test_connection')
    request = stub_request(:get, 'https://api.typesafe.ai/v1/models')
              .with(headers: { 'Authorization' => 'Bearer ts_test_connection' })
              .to_return(status: 200, body: { models: [{ name: 'jev-latest' }] }.to_json)

    post '/super_admin/app_config/test_typesafe?config=typesafe'

    expect(response).to redirect_to(super_admin_app_config_path(config: 'typesafe'))
    expect(flash[:notice]).to eq('TypeSafe AI connection is working.')
    expect(request).to have_been_requested.once
  end

  [123, ['not-a-key'], { nested: 'not-a-key' }].each do |value|
    it "rejects a credential with invalid #{value.class} shape instead of coercing it" do
      expect do
        post '/super_admin/app_config?config=typesafe', params: { app_config: { TYPESAFE_API_KEY: value } }, as: :json
      end.not_to change(AiProviderCredential, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'Invalid TypeSafe configuration.')
    end
  end
end
