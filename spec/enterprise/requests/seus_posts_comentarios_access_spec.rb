require 'rails_helper'

# Seus posts F2 (#2305), parecer da sessão Funções (29/10): ler os comentários de um post é `posts_view` e ver a caixa
# do perfil; agir (responder, privado, esconder, apagar) é `posts_manage` e ver a caixa. Sem ver a caixa, 403
# `not_inbox_member` antes de chamar a Meta. Perfil de outra conta, post de outro perfil e comentário de outro post:
# 404, sem agir. A Auditoria grava quem, o perfil, o post, o comentário e a ação, nunca o texto. Fica em
# spec/enterprise: a metade de função personalizada é EE.
RSpec.describe 'Seus posts: comentários de cada post só para quem vê a caixa (#2305)', type: :request do
  let(:account) { create(:account) }
  let(:ig_id) { '17841400000000001' }
  let(:post_id) { '17900000000000001' }
  let(:comment_id) { '18000000000000001' }
  let(:ig) { 'https://graph.instagram.com/v22.0' }
  let(:json) { { 'Content-Type' => 'application/json' } }
  let!(:canal) { create(:channel_instagram, account: account, instagram_id: ig_id, provider_name: 'lojaexemplo') }
  let(:inbox) { canal.inbox }
  let(:base) { "/api/v1/accounts/#{account.id}/seus_posts/posts/#{post_id}" }
  let(:perfil) { "instagram-#{canal.id}" }

  before do
    Rails.cache.clear
    account.enable_features!('seus_posts', 'seus_posts_comentarios')
    allow(SeusPosts::Posts).to receive(:para).and_return(
      instance_double(SeusPosts::PostsInstagram, perform: { status: 'ok', posts: [{ id: post_id, created_time: 1.day.ago.iso8601 }],
                                                            normal: {} })
    )
    # Quem espera no post: a mesma contagem do cartão da lista (SeusPosts::Esperando).
    allow(SeusPosts::Esperando).to receive(:new).and_return(
      instance_double(SeusPosts::Esperando, perform: { status: 'ok', pendentes: { post_id => { ids: %w[18000000000000001], mais: true } } })
    )
    stub_request(:get, %r{#{ig}/#{comment_id}\?}).to_return(
      status: 200, headers: json,
      body: { id: comment_id, timestamp: 1.hour.ago.iso8601, from: { id: '501', username: 'carla.dias' }, media: { id: post_id } }.to_json
    )
  end

  def member_with(permissions, caixa: true)
    user = create(:user, account: account, role: :agent)
    AccountUser.find_by(account: account, user: user).update!(custom_role: create(:custom_role, account: account, permissions: permissions))
    create(:inbox_member, user: user, inbox: inbox) if caixa
    user
  end

  # A criação da caixa pela factory inscreve o app (subscribed_apps): não é chamada dos comentários.
  def instagram_call
    a_request(:any, /graph\.instagram\.com/).with { |request| !request.uri.path.end_with?('subscribed_apps') }
  end

  def stub_lista
    stub_request(:get, %r{#{ig}/#{post_id}/comments})
      .to_return(status: 200, headers: json, body: { data: [{ id: comment_id, text: 'Tem M?', timestamp: 1.hour.ago.iso8601,
                                                              from: { id: '501', username: 'carla.dias' } }] }.to_json)
    stub_request(:get, %r{#{ig}/#{post_id}\?}).to_return(status: 200, headers: json, body: { comments_count: 1 }.to_json)
  end

  def acoes(user)
    headers = user.create_new_auth_token
    [
      -> { post "#{base}/comments/#{comment_id}/reply", params: { perfil: perfil, content: 'Oi' }, headers: headers, as: :json },
      -> { post "#{base}/comments/#{comment_id}/private_reply", params: { perfil: perfil, content: 'Oi' }, headers: headers, as: :json },
      -> { post "#{base}/comments/#{comment_id}/hide", params: { perfil: perfil, hidden: true }, headers: headers, as: :json },
      -> { delete "#{base}/comments/#{comment_id}", params: { perfil: perfil }, headers: headers, as: :json }
    ]
  end

  it 'posts_view com a caixa lê o post e os comentários, sem nenhuma ação' do
    stub_lista
    user = member_with(%w[posts_view])

    get base, params: { perfil: perfil }, headers: user.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body).to include('status' => 'ok', 'can_manage' => false)
    expect(body.dig('post', 'id')).to eq(post_id)
    row = body.dig('comments', 'comments').first
    expect(row.slice('can_reply', 'can_hide', 'can_delete', 'can_reply_private').values).to all(be(false))
  end

  it 'só posts_view: 403 em toda ação, sem chamar o Instagram' do
    acoes(member_with(%w[posts_view])).each do |acao|
      acao.call
      expect(response).to have_http_status(:forbidden)
    end
    expect(instagram_call).not_to have_been_made
  end

  it 'posts_manage sem ver a caixa: 403 not_inbox_member em ler e agir, sem chamar o Instagram' do
    user = member_with(%w[posts_manage], caixa: false)

    get base, params: { perfil: perfil }, headers: user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body['error']).to eq('not_inbox_member')
    acoes(user).each do |acao|
      acao.call
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['error']).to eq('not_inbox_member')
    end
    expect(instagram_call).not_to have_been_made
    expect(SeusPosts::Posts).not_to have_received(:para)
  end

  it 'perfil de outra conta: 404' do
    outro = create(:channel_instagram, account: create(:account))

    get base, params: { perfil: "instagram-#{outro.id}" }, headers: member_with(%w[posts_manage]).create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
  end

  it 'post que não é do perfil: 404, sem ler comentário nem agir' do
    user = member_with(%w[posts_manage])

    outro_post = "/api/v1/accounts/#{account.id}/seus_posts/posts/17900000000000099"
    get outro_post, params: { perfil: perfil }, headers: user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
    delete "#{outro_post}/comments/#{comment_id}", params: { perfil: perfil }, headers: user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
    expect(instagram_call).not_to have_been_made
  end

  it 'comentário de outro post: 404, sem agir' do
    stub_request(:get, %r{#{ig}/18000000000000077\?})
      .to_return(status: 200, headers: json, body: { id: '18000000000000077', media: { id: '17900000000000099' } }.to_json)
    apagar = stub_request(:delete, %r{#{ig}/18000000000000077})

    headers = member_with(%w[posts_manage]).create_new_auth_token
    delete "#{base}/comments/18000000000000077", params: { perfil: perfil }, headers: headers, as: :json

    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body['error']).to eq('comment_not_found')
    expect(apagar).not_to have_been_made
  end

  it 'posts_manage com a caixa responde; a Auditoria grava quem, perfil, post, comentário e ação, sem o texto' do
    stub_request(:post, %r{#{ig}/#{comment_id}/replies}).to_return(status: 200, headers: json, body: { id: '18000000000000555' }.to_json)
    user = member_with(%w[posts_manage])

    post "#{base}/comments/#{comment_id}/reply", params: { perfil: perfil, content: 'Te chamei no direct' },
                                                 headers: user.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    audit = Audited.audit_class.where(action: 'seus_posts_comment').last
    expect(audit.user).to eq(user)
    expect(audit.audited_changes).to eq('network' => 'instagram', 'perfil' => perfil, 'post_id' => post_id,
                                        'comment_id' => comment_id, 'action' => 'reply')
    expect(audit.audited_changes.to_json).not_to include('Te chamei')
    expect(Crm::MetaAdsCommentAction.find_by(comment_id: '18000000000000555', action: 'page_reply', ad_id: nil)).to be_present
  end

  it 'privado de quem não enxerga a conversa: sai, mas sem o "Ver conversa"' do
    stub_request(:post, %r{#{ig}/#{ig_id}/messages})
      .to_return(status: 200, headers: json, body: { recipient_id: '7001', message_id: 'mid.1' }.to_json)
    user = member_with(%w[posts_manage])

    post "#{base}/comments/#{comment_id}/private_reply", params: { perfil: perfil, content: 'Oi, Carla!' },
                                                         headers: user.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['sent_at']).to be_present
    expect(response.parsed_body['conversation_path']).to be_nil
  end

  describe 'Página' do
    let!(:pagina) do
      stub_request(:post, %r{graph\.facebook\.com/.*/subscribed_apps}).to_return(status: 200, headers: json, body: { success: true }.to_json)
      create(:channel_facebook_page, account: account, page_id: '700', inbox: nil).tap { |canal| create(:inbox, account: account, channel: canal) }
    end
    let(:perfil_pagina) { "facebook-#{pagina.id}" }
    let(:fb) { 'https://graph.facebook.com/v23.0' }
    let(:post_pagina) { '700_1' }

    before do
      allow(SeusPosts::Posts).to receive(:para).with(pagina, any_args).and_return(
        instance_double(SeusPosts::PostsPagina, perform: { status: 'ok', posts: [{ id: post_pagina, created_time: 1.day.ago.iso8601 }],
                                                           normal: {} })
      )
    end

    def manager_da_pagina
      user = member_with(%w[posts_manage], caixa: false)
      create(:inbox_member, user: user, inbox: pagina.inbox)
      user
    end

    def facebook_call
      a_request(:any, /graph\.facebook\.com/).with { |request| !request.uri.path.end_with?('subscribed_apps') }
    end

    it 'só posts_view: 403; posts_manage sem a caixa do Messenger: 403 not_inbox_member; sem chamar a Meta' do
      so_ve = member_with(%w[posts_view], caixa: false)
      create(:inbox_member, user: so_ve, inbox: pagina.inbox)
      sem_caixa = member_with(%w[posts_manage], caixa: false)
      caminho = "/api/v1/accounts/#{account.id}/seus_posts/posts/#{post_pagina}/comments/1_10"

      delete caminho, params: { perfil: perfil_pagina }, headers: so_ve.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      delete caminho, params: { perfil: perfil_pagina }, headers: sem_caixa.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['error']).to eq('not_inbox_member')
      expect(facebook_call).not_to have_been_made
    end

    it 'comentário de outro post da Página: 404, sem chamar a Meta' do
      headers = manager_da_pagina.create_new_auth_token
      delete "/api/v1/accounts/#{account.id}/seus_posts/posts/#{post_pagina}/comments/2_10",
             params: { perfil: perfil_pagina }, headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
      expect(facebook_call).not_to have_been_made
    end

    it 'esconde como a Página e grava a ação sem anúncio' do
      esconder = stub_request(:post, %r{graph\.facebook\.com/v\d+\.\d+/1_10}).to_return(status: 200, headers: json, body: { success: true }.to_json)

      post "/api/v1/accounts/#{account.id}/seus_posts/posts/#{post_pagina}/comments/1_10/hide",
           params: { perfil: perfil_pagina, hidden: true }, headers: manager_da_pagina.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(esconder).to have_been_made
      expect(Crm::MetaAdsCommentAction.find_by(network: 'facebook', comment_id: '1_10', action: 'hide', ad_id: nil)).to be_present
    end
  end
end
