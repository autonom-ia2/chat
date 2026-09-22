require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Portals', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent_1) { create(:user, account: account, role: :agent) }
  let(:agent_2) { create(:user, account: account, role: :agent) }
  let!(:portal) { create(:portal, slug: 'portal-1', name: 'test_portal', account_id: account.id) }

  describe 'GET /api/v1/accounts/{account.id}/portals' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/portals"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      it 'get all portals' do
        portal2 = create(:portal, name: 'test_portal_2', account_id: account.id, slug: 'portal-2')
        expect(portal2.id).not_to be_nil
        get "/api/v1/accounts/#{account.id}/portals",
            headers: admin.create_new_auth_token

        expect(response).to have_http_status(:success)
        json_response = response.parsed_body
        expect(json_response['payload'].length).to be 2
        expect(json_response['payload'][0]['id']).to be portal.id
      end
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/portals/{portal.slug}' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/portals"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      it 'get one portals' do
        get "/api/v1/accounts/#{account.id}/portals/#{portal.slug}",
            headers: admin.create_new_auth_token

        expect(response).to have_http_status(:success)
        json_response = response.parsed_body
        expect(json_response['name']).to eq portal.name
        expect(json_response['meta']['all_articles_count']).to eq 0
      end

      it 'returns portal articles metadata' do
        portal.update(config: { allowed_locales: %w[en es], default_locale: 'en' })
        en_cat = create(:category, locale: :en, portal_id: portal.id, slug: 'en-cat')
        es_cat = create(:category, locale: :es, portal_id: portal.id, slug: 'es-cat')
        create(:article, category_id: en_cat.id, portal_id: portal.id, author_id: agent.id)
        create(:article, category_id: en_cat.id, portal_id: portal.id, author_id: admin.id)
        create(:article, category_id: es_cat.id, portal_id: portal.id, author_id: agent.id)

        get "/api/v1/accounts/#{account.id}/portals/#{portal.slug}?locale=en",
            headers: admin.create_new_auth_token

        expect(response).to have_http_status(:success)
        json_response = response.parsed_body
        expect(json_response['name']).to eq portal.name
        expect(json_response['meta']['all_articles_count']).to eq 2
        expect(json_response['meta']['mine_articles_count']).to eq 1
      end

      it 'returns not found for a slug that does not exist' do
        get "/api/v1/accounts/#{account.id}/portals/nonexistent-slug",
            headers: admin.create_new_auth_token

        expect(response).to have_http_status(:not_found)
        expect(response.parsed_body['error']).to eq 'Resource could not be found'
      end

      it 'returns not found for a slug that belongs to another account' do
        other_portal = create(:portal)

        get "/api/v1/accounts/#{account.id}/portals/#{other_portal.slug}",
            headers: admin.create_new_auth_token

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/portals' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/portals",
             params: {},
             headers: agent.create_new_auth_token

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      it 'does not allow administrators to create a portal' do
        portal_params = {
          portal: {
            name: 'test_portal',
            slug: 'test_kbase',
            custom_domain: 'https://support.chatwoot.dev'
          }
        }

        expect do
          post "/api/v1/accounts/#{account.id}/portals",
               params: portal_params,
               headers: admin.create_new_auth_token
        end.not_to change(Portal, :count)

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'PUT /api/v1/accounts/{account.id}/portals/{portal.slug}' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        put "/api/v1/accounts/#{account.id}/portals/#{portal.slug}", params: {}

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      it 'does not allow administrators to update a portal' do
        portal_params = {
          portal: {
            name: 'updated_test_portal',
            config: { 'allowed_locales' => %w[en es], 'draft_locales' => ['es'], 'default_locale' => 'en' }
          }
        }

        expect(portal.name).to eql('test_portal')

        put "/api/v1/accounts/#{account.id}/portals/#{portal.slug}",
            params: portal_params,
            headers: admin.create_new_auth_token

        expect(response).to have_http_status(:unauthorized)
        expect(portal.reload.name).to eql('test_portal')
      end
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/portals/{portal.slug}' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        delete "/api/v1/accounts/#{account.id}/portals/#{portal.slug}", params: {}
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      it 'does not allow administrators to delete a portal' do
        expect do
          delete "/api/v1/accounts/#{account.id}/portals/#{portal.slug}",
                 headers: admin.create_new_auth_token
        end.not_to change(Portal, :count)

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  # Portal members endpoint removed

  describe 'DELETE /api/v1/accounts/{account.id}/portals/{portal.slug}/logo' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        delete "/api/v1/accounts/#{account.id}/portals/#{portal.slug}/logo"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      before do
        portal.logo.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'avatar.png', content_type: 'image/png')
      end

      it 'throw error if agent' do
        delete "/api/v1/accounts/#{account.id}/portals/#{portal.slug}/logo",
               headers: agent.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'does not allow administrators to delete the portal logo' do
        delete "/api/v1/accounts/#{account.id}/portals/#{portal.slug}/logo",
               headers: admin.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(portal.logo.attachment.reload).to be_present
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/portals/{portal.slug}/send_instructions' do
    let(:portal_with_domain) { create(:portal, slug: 'portal-with-domain', account_id: account.id, custom_domain: 'docs.example.com') }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/portals/#{portal_with_domain.slug}/send_instructions",
             params: { email: 'dev@example.com' }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated agent' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/portals/#{portal_with_domain.slug}/send_instructions",
             headers: agent.create_new_auth_token,
             params: { email: 'dev@example.com' },
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated admin' do
      it 'does not allow administrators to send instructions' do
        mailer_double = instance_double(ActionMailer::MessageDelivery)
        allow(PortalInstructionsMailer).to receive(:send_cname_instructions).and_return(mailer_double)
        allow(mailer_double).to receive(:deliver_later)

        post "/api/v1/accounts/#{account.id}/portals/#{portal_with_domain.slug}/send_instructions",
             headers: admin.create_new_auth_token,
             params: { email: 'dev@example.com' },
             as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(PortalInstructionsMailer).not_to have_received(:send_cname_instructions)
      end
    end
  end
end
