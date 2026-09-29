require 'rails_helper'

RSpec.describe 'Relationships configuration', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/relationships/configuration" }

  it 'denies extension endpoints with flags off' do
    get url, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:forbidden)
  end

  it 'requires the base attributes feature for configuration reads and writes' do
    account.enable_features!('relationships_attributes')
    account.disable_features!('custom_attributes')
    headers = admin.create_new_auth_token
    get url, headers: headers
    expect(response).to have_http_status(:forbidden)
    patch url, headers: headers, params: { configuration: { revision: 0, surfaces: {} } }, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(account.reload.settings['relationships']).to be_nil
  end

  it 'allows reads but denies definition and layout management to an ordinary agent' do
    account.enable_features!('custom_attributes', 'relationships_attributes')
    get url, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['can_manage']).to be(false)
    patch url, headers: agent.create_new_auth_token, params: { configuration: { revision: 0, surfaces: {} } }, as: :json
    # Existing Pundit handler returns 401 for denied management.
    expect(response).to have_http_status(:unauthorized)
  end

  it 'returns explicit conflicts and validates shape' do
    account.enable_features!('custom_attributes', 'relationships_attributes')
    headers = admin.create_new_auth_token
    patch url, headers: headers, params: { configuration: { revision: 0, surfaces: {} } }, as: :json
    expect(response).to have_http_status(:ok)
    patch url, headers: headers, params: { configuration: { revision: 0, surfaces: {} } }, as: :json
    expect(response).to have_http_status(:conflict)
    patch url, headers: headers, params: { configuration: { revision: '1', surfaces: {} } }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'rejects cross-account definitions and malformed configuration objects' do
    account.enable_features!('custom_attributes', 'relationships_attributes')
    foreign = create(:custom_attribute_definition, attribute_model: 'contact_attribute')
    patch url, headers: admin.create_new_auth_token,
               params: { configuration: { revision: 0, surfaces: { contact_details: { mode: 'custom', ids: [foreign.id] } } } }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(account.reload.settings['relationships']).to be_nil
    patch url, headers: admin.create_new_auth_token, params: { configuration: 'invalid' }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'does not enable navigation or media when attribute presentation is enabled' do
    account.enable_features!('custom_attributes', 'relationships_attributes')
    expect(account.feature_enabled?('relationships_navigation')).to be(false)
    expect(account.feature_enabled?('relationships_company_media')).to be(false)
  end
end
