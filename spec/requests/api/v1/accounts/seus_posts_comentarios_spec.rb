require 'rails_helper'

# Seus posts F2 (#2305): o post e os comentários dele. Atrás das flags `seus_posts` e `seus_posts_comentarios` (404 sem
# qualquer uma, sem chamar a Meta); ids fora do formato da Graph, 404. O administrador manda o privado e recebe o
# caminho da conversa. O acesso por função está em spec/enterprise/requests/seus_posts_comentarios_access_spec.rb.
RSpec.describe 'Seus posts: comentários de cada post', type: :request do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:admin) { account_and_user.last }
  let(:ig_id) { '17841400000000001' }
  let(:post_id) { '17900000000000001' }
  let(:comment_id) { '18000000000000001' }
  let(:ig) { 'https://graph.instagram.com/v22.0' }
  let(:json) { { 'Content-Type' => 'application/json' } }
  let!(:canal) { create(:channel_instagram, account: account, instagram_id: ig_id, provider_name: 'lojaexemplo') }
  let(:base) { "/api/v1/accounts/#{account.id}/seus_posts/posts/#{post_id}" }
  let(:perfil) { "instagram-#{canal.id}" }

  before do
    Rails.cache.clear
    account.enable_features!('seus_posts', 'seus_posts_comentarios')
    allow(SeusPosts::Posts).to receive(:para).and_return(
      instance_double(SeusPosts::PostsInstagram, perform: { status: 'ok', posts: [{ id: post_id, created_time: 1.day.ago.iso8601 }],
                                                            normal: {} })
    )
  end

  it 'sem a flag seus_posts_comentarios: 404, sem ler os posts' do
    account.disable_features!('seus_posts_comentarios')

    get base, params: { perfil: perfil }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
    expect(SeusPosts::Posts).not_to have_received(:para)
  end

  it 'id fora do formato da Graph: 404, sem ler os posts' do
    %w[17900000000000001x 1_2_3 _1].each do |id|
      get "/api/v1/accounts/#{account.id}/seus_posts/posts/#{id}", params: { perfil: perfil }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
    expect(SeusPosts::Posts).not_to have_received(:para)
  end

  it 'sem a permissão de ler comentários: o post vem, e os comentários dizem needs_permission' do
    stub_request(:get, %r{#{ig}/#{post_id}/comments})
      .to_return(status: 403, headers: json, body: { error: { code: 10, message: 'x' } }.to_json)

    get base, params: { perfil: perfil }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('comments', 'status')).to eq('needs_permission')
    expect(response.parsed_body['can_manage']).to be(true)
  end

  def stub_comentario
    stub_request(:get, %r{#{ig}/#{comment_id}\?}).to_return(
      status: 200, headers: json,
      body: { id: comment_id, timestamp: 1.hour.ago.iso8601, from: { id: '501', username: 'carla.dias' }, media: { id: post_id } }.to_json
    )
  end

  def headers
    admin.create_new_auth_token
  end

  it 'Meta fora só nos comentários: o post vem, e os comentários dizem meta_unavailable' do
    stub_request(:get, %r{#{ig}/#{post_id}/comments}).to_return(status: 503, headers: json, body: { error: { code: 2 } }.to_json)

    get base, params: { perfil: perfil }, headers: headers, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('post', 'id')).to eq(post_id)
    expect(response.parsed_body['comments']).to include('status' => 'meta_unavailable', 'total' => nil)
  end

  it 'Meta fora ao conferir o comentário: 422 meta_unavailable, não 404' do
    stub_request(:get, %r{#{ig}/#{comment_id}\?}).to_return(status: 503, headers: json, body: { error: { code: 2 } }.to_json)

    delete "#{base}/comments/#{comment_id}", params: { perfil: perfil }, headers: headers, as: :json

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body['error']).to eq('meta_unavailable')
  end

  it 'esconde e apaga, grava as ações sem anúncio e esquece "esperando você" do perfil' do
    stub_comentario
    stub_request(:post, %r{#{ig}/#{comment_id}\?}).to_return(status: 200, headers: json, body: { success: true }.to_json)
    stub_request(:delete, %r{#{ig}/#{comment_id}\?}).to_return(status: 200, headers: json, body: { success: true }.to_json)
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    chave = SeusPosts::Leitura.chave(account.id, "esperando:#{perfil}")
    Rails.cache.write(chave, { status: 'ok' })
    Rails.cache.write("#{chave}:ultima", { status: 'ok' })

    post "#{base}/comments/#{comment_id}/hide", params: { perfil: perfil, hidden: true }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    delete "#{base}/comments/#{comment_id}", params: { perfil: perfil }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)

    expect(Crm::MetaAdsCommentAction.where(comment_id: comment_id, ad_id: nil).pluck(:action)).to contain_exactly('hide', 'delete')
    expect(Rails.cache.read(chave)).to be_nil
    expect(Rails.cache.read("#{chave}:ultima")).to be_nil
  end

  it '"Não foi enviado": libera só o privado sem confirmação do post, e recusa o que não está pendente' do
    stub_comentario
    action = Crm::MetaAdsCommentAction.record!(account: account, network: 'instagram', comment_id: comment_id, action: 'private_reply',
                                               actor: 'user', user: admin, attempted_at: 5.minutes.ago, failed_at: 4.minutes.ago)

    post "#{base}/comments/#{comment_id}/private_reply/release", params: { perfil: perfil }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(Crm::MetaAdsCommentAction.exists?(action.id)).to be(false)

    post "#{base}/comments/#{comment_id}/private_reply/release", params: { perfil: perfil }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body['error']).to eq('private_reply_not_pending')
  end

  it 'o administrador manda o privado e recebe o caminho da conversa' do
    stub_comentario
    stub_request(:post, %r{#{ig}/#{ig_id}/messages})
      .to_return(status: 200, headers: json, body: { recipient_id: '7001', message_id: 'mid.1' }.to_json)

    post "#{base}/comments/#{comment_id}/private_reply", params: { perfil: perfil, content: 'Oi, Carla!' },
                                                         headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['conversation_path']).to start_with("/app/accounts/#{account.id}/conversations/")
    expect(Crm::MetaAdsCommentAction.find_by(comment_id: comment_id, action: 'private_reply', ad_id: nil)).to be_present
  end
end
