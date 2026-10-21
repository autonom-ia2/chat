require 'rails_helper'

# #2027: connecting a channel creates an inbox, so a custom role reaches it only with inbox_manage.
RSpec.describe 'Connect channel with a custom role', type: :request do
  let(:account) { create(:account) }
  let(:koala_api) { instance_double(Koala::Facebook::API) }
  let(:koala_oauth) { instance_double(Koala::Facebook::OAuth) }

  def custom_role_user(*permissions)
    user = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: permissions)
    user.account_users.find_by(account: account).update!(custom_role: role)
    user
  end

  before do
    allow(Koala::Facebook::OAuth).to receive(:new).and_return(koala_oauth)
    allow(koala_oauth).to receive(:exchange_access_token_info).and_return('access_token' => SecureRandom.hex(10))
    allow(Koala::Facebook::API).to receive(:new).and_return(koala_api)
    allow(koala_api).to receive(:get_connections).with('me', 'accounts').and_return([])
  end

  it 'lets inbox_manage list the Facebook pages to connect' do
    post "/api/v1/accounts/#{account.id}/callbacks/facebook_pages",
         headers: custom_role_user('inbox_manage').create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
  end

  it 'keeps inbox_view out' do
    post "/api/v1/accounts/#{account.id}/callbacks/facebook_pages",
         headers: custom_role_user('inbox_view').create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
