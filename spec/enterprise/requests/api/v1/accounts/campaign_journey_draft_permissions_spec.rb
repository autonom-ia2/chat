require 'rails_helper'

# #1898: quem vê campanhas vê os rascunhos; quem gerencia monta; apagar é do autor ou de quem dispara.
RSpec.describe 'Campaign journey draft permissions (#1898)', :aggregate_failures, type: :request do
  around do |example|
    with_modified_env(CAMPAIGN_JOURNEY_ENABLED: 'true') { example.run }
  end

  let(:account) { create(:account) }
  let(:path) { "/api/v1/accounts/#{account.id}/campaign_journey/drafts" }

  def member(permissions)
    user = create(:user, account: account, role: :agent)
    user.account_users.find_by!(account: account).update!(custom_role: create(:custom_role, account: account, permissions: permissions))
    user
  end

  def headers(user)
    user.create_new_auth_token
  end

  it 'lets campaign_view read but not write' do
    viewer = member(['campaign_view'])
    draft = CampaignJourneyDraft.create!(account: account, title: 'Pronta')

    get path, headers: headers(viewer), as: :json
    expect(response).to have_http_status(:ok)
    get "#{path}/#{draft.id}", headers: headers(viewer), as: :json
    expect(response).to have_http_status(:ok)

    post path, params: { draft: { title: 'Nova' } }, headers: headers(viewer), as: :json
    expect(response).to have_http_status(:unauthorized)
    patch "#{path}/#{draft.id}", params: { draft: { title: 'Mudou' } }, headers: headers(viewer), as: :json
    expect(response).to have_http_status(:unauthorized)
    delete "#{path}/#{draft.id}", headers: headers(viewer), as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(draft.reload.title).to eq('Pronta')
  end

  it 'lets campaign_manage build and remove its own draft, but not the draft of someone else' do
    author = member(['campaign_manage'])
    colleague = member(['campaign_manage'])

    post path, params: { draft: { title: 'Minha', channel: 'sms' } }, headers: headers(author), as: :json
    expect(response).to have_http_status(:created)
    mine = CampaignJourneyDraft.find(response.parsed_body.dig('payload', 'id'))
    expect(mine.user).to eq(author)

    patch "#{path}/#{mine.id}", params: { draft: { title: 'Ajustada' } }, headers: headers(colleague), as: :json
    expect(response).to have_http_status(:ok)

    delete "#{path}/#{mine.id}", headers: headers(colleague), as: :json
    expect(response).to have_http_status(:unauthorized)
    delete "#{path}/#{mine.id}", headers: headers(author), as: :json
    expect(response).to have_http_status(:no_content)
  end

  it 'takes the delete away from an author who no longer manages campaigns' do
    author = member(['campaign_manage'])
    draft = CampaignJourneyDraft.create!(account: account, user: author, title: 'Minha')
    author.account_users.find_by!(account: account).custom_role.update!(permissions: ['campaign_view'])

    delete "#{path}/#{draft.id}", headers: headers(author), as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(draft.reload).to be_present
  end

  it 'keeps the draft when the author leaves, and the administrator can still remove it' do
    author = member(['campaign_manage'])
    draft = CampaignJourneyDraft.create!(account: account, user: author, title: 'Órfã')
    admin = create(:user, account: account, role: :administrator)

    author.destroy!
    expect(draft.reload.user_id).to be_nil

    delete "#{path}/#{draft.id}", headers: headers(admin), as: :json
    expect(response).to have_http_status(:no_content)
  end
end
