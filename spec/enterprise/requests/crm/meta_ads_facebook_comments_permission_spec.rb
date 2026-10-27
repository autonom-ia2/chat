require 'rails_helper'

# Comentários do anúncio no Facebook (#2197) com funções personalizadas: `meta_ads_view` lê sem poder agir (linhas
# com can_* false, ações 403 sem chamar a Meta); `meta_ads_manage` age. Em spec/enterprise: a metade de função
# personalizada do permission_granted? é EE.
RSpec.describe 'Anúncios da Meta: comentários do Facebook com funções (#2197)', type: :request do
  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true' do
      example.run
    end
  end

  let(:account) { create_account_and_user.first }
  let(:ad_id) { '120254710382770416' }
  let(:page_id) { '100000000000001' }
  let(:post_id) { "#{page_id}_200000000000002" }
  let(:comment_id) { '200000000000002_300000000000003' }
  let(:path) { "/api/v1/accounts/#{account.id}/crm/meta_ads_connection/ads/#{ad_id}/facebook_comments" }
  let(:json) { { 'Content-Type' => 'application/json' } }

  before do
    account.enable_features!('meta_ads_comentarios_facebook')
    create_meta_ads_insights_connection(account)
    simulate_meta_ads_comment_pieces(account_ids: [account.id])
    stub_request(:get, meta_graph_url('me/permissions'))
      .to_return(status: 200, headers: json, body: { data: %w[pages_read_user_content pages_manage_engagement]
        .map { |name| { permission: name, status: 'granted' } } }.to_json)
    stub_request(:get, meta_graph_url(ad_id)).with(query: hash_including({}))
                                             .to_return(status: 200, headers: json,
                                                        body: { id: ad_id, account_id: '2196424464528988', status: 'ACTIVE',
                                                                creative: { id: '9', effective_object_story_id: post_id } }.to_json)
    stub_request(:get, meta_graph_url(page_id)).with(query: { fields: 'access_token,name' })
                                               .to_return(status: 200, body: { access_token: 'PAGETOKEN123' }.to_json, headers: json)
  end

  def pessoa_com(permissions)
    user = create(:user, account: account, role: :agent)
    role = CustomRole.create!(account: account, name: "Cargo #{SecureRandom.hex(4)}", permissions: permissions)
    AccountUser.find_by(account: account, user: user).update!(custom_role: role)
    user
  end

  it 'meta_ads_view lê sem poder agir, e apagar é recusado sem chamar a Meta' do
    viewer = pessoa_com(%w[meta_ads_view])
    stub_request(:get, meta_graph_url(post_id)).with(query: hash_including({}))
                                               .to_return(status: 200, headers: json, body: {
                                                 comments: { data: [{ id: comment_id, from: { id: '5', name: 'Mariana' }, message: 'Oi',
                                                                      can_comment: true, can_hide: true, can_remove: true,
                                                                      comments: { data: [{ id: '200000000000002_4', can_remove: true }] } }] }
                                               }.to_json)

    get path, headers: viewer.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    row = response.parsed_body.dig('comments', 'comments', 0)
    expect(row.values_at('can_reply', 'can_hide', 'can_delete')).to eq([false, false, false])
    expect(row.dig('replies', 0, 'can_delete')).to be(false)

    delete "#{path}/#{comment_id}", headers: viewer.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(a_request(:delete, /graph\.facebook\.com/)).not_to have_been_made
  end

  it 'meta_ads_manage apaga' do
    manager = pessoa_com(%w[meta_ads_manage])
    stub_request(:delete, meta_graph_url(comment_id)).to_return(status: 200, body: { success: true }.to_json, headers: json)

    delete "#{path}/#{comment_id}", headers: manager.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
  end
end
