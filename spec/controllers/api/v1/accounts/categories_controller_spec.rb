require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Categories', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let!(:portal) { create(:portal, name: 'test_portal', account_id: account.id, config: { allowed_locales: %w[en es] }) }
  let!(:category) { create(:category, name: 'category', portal: portal, account_id: account.id, slug: 'category_slug', position: 1) }
  let!(:category_to_associate) do
    create(:category, name: 'associated category', portal: portal, account_id: account.id, slug: 'associated_category_slug', position: 2)
  end
  let!(:related_category_1) do
    create(:category, name: 'related category 1', portal: portal, account_id: account.id, slug: 'category_slug_1', position: 3)
  end
  let!(:related_category_2) do
    create(:category, name: 'related category 2', portal: portal, account_id: account.id, slug: 'category_slug_2', position: 4)
  end

  describe 'POST /api/v1/accounts/{account.id}/portals/{portal.slug}/categories' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/portals/#{portal.slug}/categories", params: {}
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let!(:category_params) do
        {
          category: {
            name: 'test_category',
            description: 'test_description',
            position: 5,
            locale: 'es',
            slug: 'test_category_1',
            parent_category_id: category.id,
            associated_category_id: category_to_associate.id,
            related_category_ids: [related_category_1.id, related_category_2.id]
          }
        }
      end

      it 'does not allow administrators to create a category' do
        expect do
          post "/api/v1/accounts/#{account.id}/portals/#{portal.slug}/categories",
               params: category_params,
               headers: admin.create_new_auth_token
        end.not_to change(Category, :count)

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'PUT /api/v1/accounts/{account.id}/portals/{portal.slug}/categories/{category.id}' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        put "/api/v1/accounts/#{account.id}/portals/#{portal.slug}/categories/#{category.id}", params: {}
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      it 'does not allow administrators to update a category' do
        category_params = {
          category: {
            name: 'test_category_2',
            description: 'test_description',
            position: 1,
            related_category_ids: [related_category_1.id],
            parent_category_id: related_category_2.id
          }
        }

        expect(category.name).not_to eql(category_params[:category][:name])

        put "/api/v1/accounts/#{account.id}/portals/#{portal.slug}/categories/#{category.id}",
            params: category_params,
            headers: admin.create_new_auth_token

        expect(response).to have_http_status(:unauthorized)
        expect(category.reload.name).not_to eql(category_params[:category][:name])
      end
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/portals/{portal.slug}/categories/{category.id}' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        delete "/api/v1/accounts/#{account.id}/portals/#{portal.slug}/categories/#{category.id}", params: {}
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      it 'does not allow administrators to delete a category' do
        expect do
          delete "/api/v1/accounts/#{account.id}/portals/#{portal.slug}/categories/#{category.id}",
                 headers: admin.create_new_auth_token
        end.not_to change(Category, :count)

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/portals/{portal.slug}/categories/reorder' do
    let(:positions_hash) do
      {
        category.id => 40,
        category_to_associate.id => 10,
        related_category_1.id => 30,
        related_category_2.id => 20
      }
    end

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/portals/#{portal.slug}/categories/reorder",
             params: { positions_hash: positions_hash }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      it 'does not allow administrators to reorder categories' do
        original_position = category.position

        post "/api/v1/accounts/#{account.id}/portals/#{portal.slug}/categories/reorder",
             params: { positions_hash: positions_hash },
             headers: admin.create_new_auth_token

        expect(response).to have_http_status(:unauthorized)
        expect(category.reload.position).to eq(original_position)
      end

      it 'returns not found when portal does not exist' do
        post "/api/v1/accounts/#{account.id}/portals/invalid-portal-slug/categories/reorder",
             params: { positions_hash: positions_hash },
             headers: admin.create_new_auth_token

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/portals/{portal.slug}/categories' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/portals/#{portal.slug}/categories"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      it 'get all categories in portal' do
        category_count = Category.all.count

        category2 = create(:category, name: 'test_category_2', portal: portal, locale: 'es', slug: 'category_slug_2')

        expect(category2.id).not_to be_nil

        get "/api/v1/accounts/#{account.id}/portals/#{portal.slug}/categories",
            headers: admin.create_new_auth_token
        expect(response).to have_http_status(:success)
        json_response = response.parsed_body
        expect(json_response['payload'].count).to be(category_count + 1)
      end
    end
  end
end
