require 'rails_helper'

RSpec.describe 'Article Bulk Actions API', type: :request do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let!(:portal) { create(:portal, name: 'test_portal', account: account, config: { allowed_locales: %w[en es fr] }) }
  let!(:category_en) { create(:category, portal: portal, account: account, locale: 'en', slug: 'getting-started') }
  let!(:category_es) { create(:category, portal: portal, account: account, locale: 'es', slug: 'primeros-pasos') }
  let!(:article_one) { create(:article, category: category_en, portal: portal, account: account, author_id: admin.id) }
  let!(:article_two) { create(:article, category: category_en, portal: portal, account: account, author_id: admin.id) }

  let(:translate_url) { "/api/v1/accounts/#{account.id}/portals/#{portal.slug}/articles/bulk_actions/translate" }

  describe 'POST articles/bulk_actions/translate' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        post translate_url, params: { ids: [article_one.id], locale: 'es', category_id: category_es.id }, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated as agent' do
      it 'returns unauthorized' do
        post translate_url,
             headers: agent.create_new_auth_token,
             params: { ids: [article_one.id], locale: 'es', category_id: category_es.id },
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    # A Central de Ajuda é só leitura (#501): nem o administrador traduz em massa.
    context 'when authenticated as admin' do
      before do
        account.enable_features!('captain_tasks')
      end

      it 'returns unauthorized and enqueues nothing' do
        expect do
          post translate_url,
               headers: admin.create_new_auth_token,
               params: { ids: [article_one.id, article_two.id], locale: 'es', category_id: category_es.id },
               as: :json
        end.not_to have_enqueued_job(Captain::Articles::TranslateJob)

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
