require 'rails_helper'

# Anúncios da Meta (#1047): portfólio parceiro e usuário do sistema da plataforma no Super Admin. O token é
# só de escrita: vai cifrado para AiProviderCredential e nunca volta para a página.
RSpec.describe 'Super Admin Meta Ads configuration', type: :request do
  let(:super_admin) { create(:super_admin) }

  before do
    sign_in(super_admin, scope: :super_admin)
    enable_test_encryption!
  end

  it 'shows the Meta Ads card in settings' do
    get '/super_admin/settings'

    expect(response).to have_http_status(:success)
    expect(response.body).to include('/super_admin/app_config?config=meta_ads')
  end

  it 'renders the page without returning the saved token' do
    AiProviderCredential.create!(provider: 'meta_ads', api_key: 'EAAGnunca_deve_aparecer')

    get '/super_admin/app_config?config=meta_ads'

    expect(response).to have_http_status(:success)
    expect(response.body).to include('Meta Ads partner business ID')
    expect(response.body).to include('Token configured. The saved token is never returned to this page.')
    expect(response.body).not_to include('EAAGnunca_deve_aparecer')
  end

  it 'stores the token encrypted and the IDs in InstallationConfig' do
    post '/super_admin/app_config?config=meta_ads', params: {
      app_config: { META_ADS_PARTNER_BUSINESS_ID: '555000111222333', META_ADS_SYSTEM_USER_ID: '61589197595551',
                    META_ADS_PLATFORM_TOKEN: 'EAAGtoken_do_formulario' }
    }

    expect(response).to redirect_to(super_admin_settings_path)
    credential = AiProviderCredential.find_by!(provider: 'meta_ads')
    raw = AiProviderCredential.connection.select_value("SELECT api_key FROM ai_provider_credentials WHERE id = #{credential.id.to_i}")
    expect(raw).not_to include('EAAGtoken_do_formulario')
    expect(credential.api_key).to eq('EAAGtoken_do_formulario')
    expect(InstallationConfig.find_by(name: 'META_ADS_PLATFORM_TOKEN')&.value).to be_nil
    expect(Crm::MetaAds::Platform.business_id).to eq('555000111222333')
    expect(Crm::MetaAds::Platform.system_user_id).to eq('61589197595551')
    expect(Crm::MetaAds::Platform).to be_configured
  end

  it 'keeps the current token when the field comes blank' do
    AiProviderCredential.create!(provider: 'meta_ads', api_key: 'EAAGtoken_atual')

    post '/super_admin/app_config?config=meta_ads', params: { app_config: { META_ADS_PLATFORM_TOKEN: '', META_ADS_PARTNER_BUSINESS_ID: '1' } }

    expect(AiProviderCredential.find_by!(provider: 'meta_ads').api_key).to eq('EAAGtoken_atual')
  end
end
