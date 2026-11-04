require 'rails_helper'

# Comentários na caixa (#2215) com funções personalizadas: ler o comentário é ler a conversa (view?); responder em
# público e esconder são escrever na conversa (show?); apagar segue a régua de apagar mensagem (delete_message?, chave
# conversation_message_delete). Quem não pode não chega a chamar a Meta.
RSpec.describe 'Comentário do Instagram na conversa: acesso por função (#2215)', type: :request do
  let(:account) { create(:account) }
  let(:post_id) { '17900000000000001' }
  let(:comment_id) { '18000000000000001' }
  let(:ig) { 'https://graph.instagram.com/v22.0' }
  let(:json) { { 'Content-Type' => 'application/json' } }
  let!(:canal) { create(:channel_instagram, account: account, instagram_id: '17841400000000001', provider_name: 'lojaexemplo') }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:origem) { { 'network' => 'instagram', 'comment_id' => comment_id, 'post_id' => post_id } }
  let(:conversation) do
    create(:conversation, account: account, inbox: canal.inbox, assignee: agent, additional_attributes: { 'meta_ads_comment' => origem })
  end
  let(:base) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/comentario" }

  before do
    account.enable_features!('meta_ads_comentarios_ia')
    # A prova do servidor de que a conversa nasceu do comentário: a linha que o motor da IA grava (#2212).
    Crm::MetaAdsCommentAction.record!(account: account, network: 'instagram', comment_id: comment_id, action: 'private_reply',
                                      actor: 'ai', conversation: conversation)
    create(:inbox_member, inbox: canal.inbox, user: agent)
    stub_request(:get, %r{#{ig}/#{comment_id}\?}).to_return(
      status: 200, headers: json,
      body: { id: comment_id, text: 'Oi', timestamp: 1.hour.ago.iso8601, from: { id: '501', username: 'c' }, media: { id: post_id } }.to_json
    )
  end

  def give_role(permissions)
    role = create(:custom_role, account: account, permissions: permissions)
    agent.account_users.find_by!(account: account).update!(custom_role: role)
  end

  def headers
    agent.create_new_auth_token
  end

  def escrita_na_meta
    a_request(:post, /graph\.instagram\.com/).with { |request| !request.uri.path.end_with?('subscribed_apps') }
  end

  it 'quem só lê vê o comentário sem nenhuma ação, e não responde nem esconde' do
    give_role(%w[conversation_view])

    get base, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['pode']).to eq('responder' => false, 'esconder' => false, 'apagar' => false)

    post "#{base}/responder", params: { content: 'Oi' }, headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
    post "#{base}/esconder", params: { hidden: true }, headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(escrita_na_meta).not_to have_been_made
  end

  it 'cargo que atende sem conversation_message_delete responde, mas não apaga' do
    give_role(%w[conversation_participating_manage])
    stub_request(:post, "#{ig}/#{comment_id}/replies").with(query: hash_including({}))
                                                      .to_return(status: 200, headers: json, body: { id: '18000000000000777' }.to_json)

    get base, headers: headers, as: :json
    expect(response.parsed_body['pode']).to eq('responder' => true, 'esconder' => true, 'apagar' => false)

    post "#{base}/responder", params: { content: 'Oi' }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)

    delete base, headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(a_request(:delete, /graph\.instagram\.com/)).not_to have_been_made
  end

  it 'cargo com conversation_message_delete apaga' do
    give_role(%w[conversation_participating_manage conversation_message_delete])
    apagar = stub_request(:delete, %r{#{ig}/#{comment_id}\?}).to_return(status: 200, headers: json, body: { success: true }.to_json)

    delete base, headers: headers, as: :json

    expect(response).to have_http_status(:ok)
    expect(apagar).to have_been_made.once
  end

  it 'agente sem cargo, da caixa, pode tudo' do
    get base, headers: headers, as: :json

    expect(response.parsed_body['pode']).to eq('responder' => true, 'esconder' => true, 'apagar' => true)
  end
end
