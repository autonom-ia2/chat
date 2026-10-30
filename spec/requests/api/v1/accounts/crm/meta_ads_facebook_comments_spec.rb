require 'rails_helper'

# Comentários do anúncio no Facebook (#2197): sem a flag 404 sem chamar a Meta; ler pede meta_ads_view, agir pede
# meta_ads_manage; cada ação fica na Auditoria da conta sem token e sem o texto (comentário é dado de terceiro).
RSpec.describe 'CRM meta_ads_connection Facebook comments (#2197)', type: :request do
  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true' do
      example.run
    end
  end

  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:admin) { account_and_user.last }
  let(:agent) { create_crm_agent(account: account).first }
  let(:path) { "/api/v1/accounts/#{account.id}/crm/meta_ads_connection/ads/#{ad_id}/facebook_comments" }
  let(:ad_id) { '120254710382770416' }
  let(:page_id) { '100000000000001' }
  let(:post_id) { "#{page_id}_200000000000002" }
  let(:comment_id) { '200000000000002_300000000000003' }
  let(:json) { { 'Content-Type' => 'application/json' } }

  before do
    account.enable_features!('meta_ads_comentarios_facebook')
    create_meta_ads_insights_connection(account)
    simulate_meta_ads_comment_pieces(account: account, page_id: page_id)
    # A caixa do Messenger da Página (#2359): o administrador vê toda caixa da conta.
    create(:inbox, account: account, channel: build(:channel_facebook_page, account: account, page_id: page_id))
  end

  def stub_meta
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

  it 'sem a flag responde 404 e não chama a Meta' do
    account.disable_features!('meta_ads_comentarios_facebook')

    get path, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
    expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
  end

  it 'lista os comentários do post do anúncio' do
    stub_meta
    stub_request(:get, meta_graph_url(post_id)).with(query: hash_including({}))
                                               .to_return(status: 200, headers: json, body: {
                                                 permalink_url: 'https://www.facebook.com/p/1',
                                                 comments: { data: [{ id: comment_id, from: { id: '5', name: 'Mariana' }, message: 'Oi',
                                                                      can_comment: true, can_hide: true, can_remove: true }],
                                                             summary: { total_count: 1 } }
                                               }.to_json)

    get path, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['comments']).to include('status' => 'ready', 'total' => 1)
    expect(response.parsed_body.dig('comments', 'comments', 0)).to include('id' => comment_id, 'can_delete' => true)
  end

  it 'agente sem meta_ads_view: 403' do
    get path, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:forbidden)
  end

  it 'responde e grava na Auditoria quem respondeu, sem o texto e sem o token' do
    stub_meta
    reply = stub_request(:post, meta_graph_url("#{comment_id}/comments"))
            .to_return(status: 200, body: { id: '200000000000002_9' }.to_json, headers: json)

    post "#{path}/#{comment_id}/reply", params: { content: 'Entregamos sim!' }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq('id' => '200000000000002_9')
    expect(reply).to have_been_requested.once
    audit = Audited.audit_class.where(auditable: account, action: 'meta_ads_facebook_comment').last
    expect(audit).to have_attributes(user_id: admin.id)
    expect(audit.audited_changes).to eq('ad_id' => ad_id, 'comment_id' => comment_id, 'acao' => 'reply')
    expect(audit.audited_changes.to_json).not_to include('Entregamos', 'PAGETOKEN123')
  end

  it 'resposta que não vem como texto é recusada sem chamar a Meta' do
    stub_meta

    post "#{path}/#{comment_id}/reply", params: { content: { a: 1 } }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error' => 'invalid_text')
    expect(a_request(:post, /graph\.facebook\.com/)).not_to have_been_made
  end

  it 'oculta e apaga' do
    stub_meta
    stub_request(:post, meta_graph_url(comment_id)).to_return(status: 200, body: { success: true }.to_json, headers: json)
    stub_request(:delete, meta_graph_url(comment_id)).to_return(status: 200, body: { success: true }.to_json, headers: json)

    patch "#{path}/#{comment_id}", params: { hidden: true }, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body).to eq('hidden' => true)

    delete "#{path}/#{comment_id}", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    # Ordem pelo id: sem `order` o Postgres não garante a ordem das linhas (falhou assim no #2356).
    expect(Audited.audit_class.where(auditable: account, action: 'meta_ads_facebook_comment').order(:id).map { |a| a.audited_changes['acao'] })
      .to eq(%w[hide delete])
  end

  it 'ocultar sem dizer true ou false é recusado sem chamar a Meta (não mostra comentário por engano)' do
    stub_meta

    patch "#{path}/#{comment_id}", params: {}, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error' => 'invalid_hidden')
    expect(a_request(:post, /graph\.facebook\.com/)).not_to have_been_made
  end

  it 'comentário de outro post: 404 comment_not_found' do
    stub_meta

    delete "#{path}/999_1", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body).to eq('error' => 'comment_not_found')
  end
end
