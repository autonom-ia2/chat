require 'rails_helper'

RSpec.describe 'Article Bulk Actions API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let!(:portal) { create(:portal, name: 'test_portal', account: account, config: { allowed_locales: %w[en es] }) }
  let!(:category) { create(:category, portal: portal, account: account, locale: 'en', slug: 'getting-started') }
  let!(:article_one) { create(:article, category: category, portal: portal, account: account, author: admin, status: :draft) }
  let!(:article_two) { create(:article, category: category, portal: portal, account: account, author: admin, status: :draft) }

  let(:base_url) { "/api/v1/accounts/#{account.id}/portals/#{portal.slug}/articles/bulk_actions" }

  describe 'PATCH articles/bulk_actions/update_status' do
    let(:update_status_url) { "#{base_url}/update_status" }

    context 'when unauthenticated' do
      it 'returns unauthorized' do
        patch update_status_url, params: { ids: [article_one.id], status: 'published' }, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated as agent' do
      it 'returns unauthorized' do
        patch update_status_url,
              headers: agent.create_new_auth_token,
              params: { ids: [article_one.id], status: 'published' },
              as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated as admin' do
      it 'does not allow administrators to update article status' do
        patch update_status_url,
              headers: admin.create_new_auth_token,
              params: { ids: [article_one.id, article_two.id], status: 'published' },
              as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(article_one.reload.status).to eq('draft')
        expect(article_two.reload.status).to eq('draft')
      end
    end
  end

  describe 'DELETE articles/bulk_actions/delete_articles' do
    let(:destroy_url) { "#{base_url}/delete_articles" }

    context 'when unauthenticated' do
      it 'returns unauthorized' do
        delete destroy_url, params: { ids: [article_one.id] }, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated as agent' do
      it 'returns unauthorized' do
        delete destroy_url,
               headers: agent.create_new_auth_token,
               params: { ids: [article_one.id] },
               as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated as admin' do
      it 'does not allow administrators to delete articles' do
        expect do
          delete destroy_url,
                 headers: admin.create_new_auth_token,
                 params: { ids: [article_one.id, article_two.id] },
                 as: :json
        end.not_to change(Article, :count)

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
