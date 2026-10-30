require 'rails_helper'

# Comentários do anúncio no Instagram (#2196): sem as flags, 404 sem chamar a Meta; ver pede meta_ads_view, agir pede
# meta_ads_manage (agente comum: 403); ocultar, apagar e responder no privado ficam na Auditoria da conta, sem o texto.
RSpec.describe 'CRM meta_ads_connection Instagram comments (#2196)', type: :request do
  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true' do
      example.run
    end
  end

  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:admin) { account_and_user.last }
  let(:agent) { create_crm_agent(account: account).first }
  let(:ad_id) { '120254710382770416' }
  let(:path) { "/api/v1/accounts/#{account.id}/crm/meta_ads_connection/ads/#{ad_id}/instagram_comments" }
  let(:media_id) { '17900000000000001' }
  let(:ig_id) { '17841400000000001' }
  let(:ig) { 'https://graph.instagram.com/v22.0' }
  let(:json) { { 'Content-Type' => 'application/json' } }

  before do
    create(:channel_instagram, account: account, instagram_id: ig_id, provider_name: 'lojaexemplo')
    account.enable_features!('meta_ads_gestao', 'meta_ads_comentarios_instagram')
    create_meta_ads_insights_connection(account)
    stub_request(:get, meta_graph_url(ad_id)).with(query: hash_including({}))
                                             .to_return(status: 200, headers: json,
                                                        body: { id: ad_id, account_id: '2196424464528988',
                                                                creative: { effective_instagram_media_id: media_id,
                                                                            instagram_user_id: ig_id } }.to_json)
    stub_request(:get, %r{#{ig}/18000000000000001\?}).to_return(
      status: 200, headers: json,
      body: { id: '18000000000000001', timestamp: 1.hour.ago.iso8601, from: { id: '501', username: 'carla.dias' }, media: { id: media_id } }.to_json
    )
  end

  # A criação da caixa pela factory inscreve o app (subscribed_apps): não é chamada dos comentários.
  def meta_call(host)
    a_request(:any, host).with { |request| !request.uri.path.end_with?('subscribed_apps') }
  end

  it 'sem a flag dos comentários responde 404 e não chama a Meta' do
    account.disable_features!('meta_ads_comentarios_instagram')

    get path, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
    expect(meta_call(/graph\.(facebook|instagram)\.com/)).not_to have_been_made
  end

  it 'lista os comentários para quem vê os anúncios' do
    stub_request(:get, %r{#{ig}/#{media_id}/comments})
      .to_return(status: 200, headers: json, body: { data: [{ id: '18000000000000001', text: 'Tem M?', timestamp: 1.hour.ago.iso8601,
                                                              from: { id: '501', username: 'carla.dias' } }] }.to_json)
    stub_request(:get, %r{#{ig}/#{media_id}\?}).to_return(status: 200, headers: json, body: { comments_count: 1 }.to_json)

    get path, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('status' => 'ready', 'total' => 1)
    expect(response.parsed_body['comments'].first).to include('id' => '18000000000000001', 'text' => 'Tem M?')
  end

  it 'agente comum não vê nem age' do
    get path, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)

    delete "#{path}/18000000000000001", headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(meta_call(/graph\.instagram\.com/)).not_to have_been_made
  end

  it 'apaga e grava na Auditoria quem apagou, sem o texto' do
    stub_request(:delete, %r{#{ig}/18000000000000001\?}).to_return(status: 200, headers: json, body: { success: true }.to_json)

    delete "#{path}/18000000000000001", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq('id' => '18000000000000001')
    audit = Audited.audit_class.where(auditable: account, action: 'meta_ads_comment').last
    expect(audit).to have_attributes(user_id: admin.id)
    expect(audit.audited_changes).to eq('network' => 'instagram', 'ad_id' => ad_id, 'comment_id' => '18000000000000001', 'action' => 'delete')
  end

  it 'oculta pelo id do comentário' do
    stub_request(:post, %r{#{ig}/18000000000000001\?}).to_return(status: 200, headers: json, body: { success: true }.to_json)

    post "#{path}/18000000000000001/hide", params: { hidden: true }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq('id' => '18000000000000001', 'hidden' => true)
  end

  it 'responde no privado e devolve o caminho da conversa' do
    stub_request(:post, %r{#{ig}/#{ig_id}/messages})
      .to_return(status: 200, headers: json, body: { recipient_id: '7001', message_id: 'mid.1' }.to_json)

    post "#{path}/18000000000000001/private_reply", params: { content: 'Oi, Carla!' }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    conversation = Message.find_by(source_id: 'mid.1').conversation
    expect(response.parsed_body['conversation_path']).to eq("/app/accounts/#{account.id}/conversations/#{conversation.display_id}")
  end

  it 'anúncio de outra conta de anúncios: 404 na lista e na ação, sem tocar no Instagram' do
    stub_request(:get, meta_graph_url(ad_id)).with(query: hash_including({}))
                                             .to_return(status: 200, headers: json,
                                                        body: { id: ad_id, account_id: '999',
                                                                creative: { effective_instagram_media_id: media_id,
                                                                            instagram_user_id: ig_id } }.to_json)

    get path, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
    delete "#{path}/18000000000000001", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)

    expect(meta_call(/graph\.instagram\.com/)).not_to have_been_made
  end

  it 'comentário de outra mídia: 404 em apagar, responder e no privado, sem agir' do
    stub_request(:get, %r{#{ig}/18000000000000009\?}).to_return(
      status: 200, headers: json,
      body: { id: '18000000000000009', timestamp: 1.hour.ago.iso8601, from: { id: '501', username: 'carla.dias' },
              media: { id: '17900000000000999' } }.to_json
    )
    headers = admin.create_new_auth_token

    delete "#{path}/18000000000000009", headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    post "#{path}/18000000000000009/reply", params: { content: 'Oi' }, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    post "#{path}/18000000000000009/private_reply", params: { content: 'Oi' }, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)

    expect(a_request(:delete, /graph\.instagram\.com/)).not_to have_been_made
    expect(a_request(:post, /graph\.instagram\.com/).with { |request| !request.uri.path.end_with?('subscribed_apps') }).not_to have_been_made
    expect(Crm::MetaAdsCommentAction.count).to eq(0)
  end

  it 'ocultar sem dizer se oculta ou mostra: 422, sem chamar o Instagram' do
    post "#{path}/18000000000000001/hide", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body).to eq('error' => 'invalid_hidden')
    expect(meta_call(/graph\.instagram\.com/)).not_to have_been_made
  end

  it '"Não foi enviado" libera o privado sem confirmação e fica na Auditoria; agente comum, não' do
    Crm::MetaAdsCommentAction.create!(account: account, network: 'instagram', comment_id: '18000000000000001', ad_id: ad_id,
                                      action: 'private_reply', actor: 'user', at: 1.hour.ago, attempted_at: 1.hour.ago)
    release = "#{path}/18000000000000001/private_reply/release"

    post release, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)

    post release, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(Crm::MetaAdsCommentAction.count).to eq(0)
    audit = Audited.audit_class.where(auditable: account, action: 'meta_ads_comment').last
    expect(audit.audited_changes).to include('action' => 'private_reply_release', 'comment_id' => '18000000000000001')
  end

  # #2327: o texto vai em `content`, que o log do Rails filtra; em `text` ele sairia em claro no CloudWatch.
  describe 'texto da resposta' do
    it 'chega à Meta pelo content' do
      replies = stub_request(:post, %r{#{ig}/18000000000000001/replies})
                .with(query: hash_excluding('message'), body: { message: 'Oi, Carla!' })
                .to_return(status: 200, headers: json, body: { id: '18000000000000077' }.to_json)

      post "#{path}/18000000000000001/reply", params: { content: 'Oi, Carla!' }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(replies).to have_been_made.once
      expect(request.filtered_parameters['content']).to eq('[FILTERED]')
    end

    it 'em text não é mais aceito e não chama a Meta' do
      post "#{path}/18000000000000001/reply", params: { text: 'Oi' }, headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body).to eq('error' => 'invalid_text')

      post "#{path}/18000000000000001/private_reply", params: { text: 'Oi' }, headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body).to eq('error' => 'invalid_text')

      expect(meta_call(%r{#{ig}/18000000000000001/replies|#{ig_id}/messages})).not_to have_been_made
    end

    it 'que não é texto (lista ou objeto) dá 422 e não chama a Meta' do
      actions = %w[reply private_reply]
      [['Oi'], { 'a' => 'Oi' }].each do |content|
        actions.each do |action|
          post "#{path}/18000000000000001/#{action}", params: { content: content }, headers: admin.create_new_auth_token, as: :json

          expect(response).to have_http_status(:unprocessable_content)
          expect(response.parsed_body).to eq('error' => 'invalid_text')
        end
      end

      expect(meta_call(%r{#{ig}/18000000000000001/replies|#{ig_id}/messages})).not_to have_been_made
    end
  end

  it 'erro de regra vira 422 com o código' do
    post "#{path}/18000000000000001/reply", params: { content: ' ' }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body).to eq('error' => 'invalid_text')
  end
end
