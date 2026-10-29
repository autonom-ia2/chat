require 'rails_helper'

# Comentários do anúncio no Instagram (#2196, #2358), parecer da sessão Funções: ler e agir em comentário pede, além da
# chave de Anúncios, ver a caixa do Instagram (InboxPolicy#show?), a regra de Seus posts. Sem ver a caixa: a lista diz
# o motivo no lugar dos comentários, e toda ação dá 403 antes de qualquer chamada ao Instagram. Fica em
# spec/enterprise: a metade de função personalizada é EE.
RSpec.describe 'Comentários do Instagram: ler e agir só para quem vê a caixa (#2196, #2358)', type: :request do
  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true' do
      example.run
    end
  end

  let(:account) { create(:account) }
  let(:manager) { create(:user, account: account, role: :agent) }
  let(:viewer) { create(:user, account: account, role: :agent) }
  let(:ad_id) { '120254710382770416' }
  let(:path) { "/api/v1/accounts/#{account.id}/crm/meta_ads_connection/ads/#{ad_id}/instagram_comments" }
  let(:media_id) { '17900000000000001' }
  let(:ig_id) { '17841400000000001' }
  let(:ig) { 'https://graph.instagram.com/v22.0' }
  let(:json) { { 'Content-Type' => 'application/json' } }
  let!(:inbox) { create(:channel_instagram, account: account, instagram_id: ig_id, provider_name: 'lojaexemplo').inbox }

  before do
    role = CustomRole.create!(account: account, name: 'Anúncios', permissions: %w[meta_ads_manage])
    AccountUser.find_by(account: account, user: manager).update!(custom_role: role)
    viewer_role = CustomRole.create!(account: account, name: 'Só vê anúncios', permissions: %w[meta_ads_view])
    AccountUser.find_by(account: account, user: viewer).update!(custom_role: viewer_role)
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
    stub_request(:post, %r{#{ig}/#{ig_id}/messages})
      .to_return(status: 200, headers: json, body: { recipient_id: '7001', message_id: 'mid.1' }.to_json)
  end

  def private_reply
    post "#{path}/18000000000000001/private_reply", params: { content: 'Oi, Carla!' }, headers: manager.create_new_auth_token, as: :json
  end

  # A criação da caixa pela factory inscreve o app (subscribed_apps): não é chamada dos comentários.
  def instagram_call
    a_request(:any, /graph\.instagram\.com/).with { |request| !request.uri.path.end_with?('subscribed_apps') }
  end

  def stub_list
    stub_request(:get, %r{#{ig}/#{media_id}/comments})
      .to_return(status: 200, headers: json, body: { data: [{ id: '18000000000000001', text: 'Tem M?', timestamp: 1.hour.ago.iso8601,
                                                              from: { id: '501', username: 'carla.dias' },
                                                              replies: { data: [{ id: '18000000000000002', text: 'Eu também',
                                                                                  timestamp: 1.hour.ago.iso8601,
                                                                                  from: { id: '502', username: 'ana' } }] } }] }.to_json)
    stub_request(:get, %r{#{ig}/#{media_id}\?}).to_return(status: 200, headers: json, body: { comments_count: 2 }.to_json)
  end

  it 'quem só vê os anúncios e é da caixa lê a lista sem nenhuma ação, nem nas respostas' do
    create(:inbox_member, user: viewer, inbox: inbox)
    stub_list

    get path, headers: viewer.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    first = response.parsed_body['comments'].first
    flags = %w[can_reply can_hide can_delete can_reply_private]
    [first, first['replies'].first].each { |row| expect(row.slice(*flags).values).to all(be(false)) }
  end

  it 'quem só vê os anúncios recebe 403 em toda ação, sem chamar o Instagram' do
    headers = viewer.create_new_auth_token
    post "#{path}/18000000000000001/reply", params: { content: 'Oi' }, headers: headers, as: :json
    expect(response).to have_http_status(:forbidden)
    post "#{path}/18000000000000001/hide", params: { hidden: true }, headers: headers, as: :json
    expect(response).to have_http_status(:forbidden)
    delete "#{path}/18000000000000001", headers: headers, as: :json
    expect(response).to have_http_status(:forbidden)
    post "#{path}/18000000000000001/private_reply", params: { content: 'Oi' }, headers: headers, as: :json
    expect(response).to have_http_status(:forbidden)

    expect(instagram_call).not_to have_been_made
  end

  it 'quem gere os anúncios sem ser da caixa recebe 403 em toda ação e o Instagram não é chamado' do
    headers = manager.create_new_auth_token
    expect { private_reply }.not_to change(Message, :count)

    post "#{path}/18000000000000001/reply", params: { content: 'Oi' }, headers: headers, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body).to eq('error' => 'not_inbox_member')
    post "#{path}/18000000000000001/hide", params: { hidden: true }, headers: headers, as: :json
    expect(response).to have_http_status(:forbidden)
    delete "#{path}/18000000000000001", headers: headers, as: :json
    expect(response).to have_http_status(:forbidden)

    expect(instagram_call).not_to have_been_made
    expect(Crm::MetaAdsCommentAction.count).to eq(0)
  end

  it 'quem gere os anúncios e é da caixa responde no privado' do
    create(:inbox_member, user: manager, inbox: inbox)

    private_reply

    expect(response).to have_http_status(:ok)
    expect(Message.find_by(source_id: 'mid.1')).to be_present
  end

  it 'quem não é da caixa não lê os comentários, nem os ocultos: a lista diz o motivo, sem chamar o Instagram' do
    stub_list

    [manager, viewer].each do |user|
      get path, headers: user.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('status' => 'not_inbox_member', 'account' => { 'username' => 'lojaexemplo', 'name' => nil },
                                         'comments' => [], 'total' => 0, 'next_cursor' => nil)
    end
    expect(instagram_call).not_to have_been_made
  end

  it 'quem gere os anúncios e é da caixa lê a lista com as ações' do
    create(:inbox_member, user: manager, inbox: inbox)
    stub_list

    get path, headers: manager.create_new_auth_token, as: :json

    expect(response.parsed_body['comments'].first).to include('can_reply' => true, 'can_hide' => true, 'can_reply_private' => true)
  end
end
