require 'rails_helper'

# Comentários na caixa (#2215): na conversa que nasceu de um comentário do Instagram (#2212), ler o comentário,
# responder em público, esconder/mostrar e apagar. Atrás da flag `meta_ads_comentarios_ia`. Cada ação vira atividade na
# conversa, fica na Auditoria (sem o texto) e em crm_meta_ads_comment_actions.
RSpec.describe 'Comentário do Instagram na conversa (#2215)', type: :request do
  let(:account) { create(:account) }
  let(:post_id) { '17900000000000001' }
  let(:comment_id) { '18000000000000001' }
  let(:ig) { 'https://graph.instagram.com/v22.0' }
  let(:json) { { 'Content-Type' => 'application/json' } }
  let!(:canal) { create(:channel_instagram, account: account, instagram_id: '17841400000000001', provider_name: 'lojaexemplo') }
  let(:origem) { { 'network' => 'instagram', 'comment_id' => comment_id, 'post_id' => post_id, 'from_id' => '501', 'care_id' => 1 } }
  let(:conversation) { create(:conversation, account: account, inbox: canal.inbox, additional_attributes: { 'meta_ads_comment' => origem }) }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Ana') }
  let(:headers) { admin.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/comentario" }
  let(:comentario) do
    { id: comment_id, text: 'Quanto custa?', timestamp: 1.hour.ago.iso8601, hidden: false, from: { id: '501', username: 'marina.costa' },
      media: { id: post_id } }
  end

  before do
    account.enable_features!('meta_ads_comentarios_ia')
    stub_request(:get, %r{#{ig}/#{comment_id}\?}).to_return(status: 200, headers: json, body: comentario.to_json)
  end

  def instagram_call
    a_request(:any, /graph\.instagram\.com/).with { |request| !request.uri.path.end_with?('subscribed_apps') }
  end

  def atividades
    conversation.messages.where(message_type: :activity).pluck(:content)
  end

  describe 'GET' do
    it 'lê o comentário na Meta, com o que a pessoa pode fazer' do
      get base, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq(
        'status' => 'ok',
        'comentario' => { 'id' => comment_id, 'autor' => '@marina.costa', 'texto' => 'Quanto custa?', 'quando' => comentario[:timestamp],
                          'escondido' => false, 'onde' => 'post' },
        'pode' => { 'responder' => true, 'esconder' => true, 'apagar' => true }
      )
    end

    it 'comentário de anúncio diz onde e mostra se está escondido' do
      conversation.update!(additional_attributes: { 'meta_ads_comment' => origem.merge('ad_id' => '120000000000001') })
      stub_request(:get, %r{#{ig}/#{comment_id}\?}).to_return(status: 200, headers: json, body: comentario.merge(hidden: true).to_json)

      get base, headers: headers, as: :json

      expect(response.parsed_body['comentario']).to include('onde' => 'anuncio', 'escondido' => true)
    end

    it 'sem a permissão de comentários do Instagram: needs_permission' do
      stub_request(:get, %r{#{ig}/#{comment_id}\?})
        .to_return(status: 403, headers: json, body: { error: { code: 10, message: 'perm' } }.to_json)

      get base, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('status' => 'needs_permission')
    end

    it 'comentário que a Meta não acha mais: apagado' do
      stub_request(:get, %r{#{ig}/#{comment_id}\?})
        .to_return(status: 400, headers: json, body: { error: { code: 100, error_subcode: 33, message: 'nope' } }.to_json)

      get base, headers: headers, as: :json

      expect(response.parsed_body).to include('status' => 'apagado')
    end

    it 'comentário de outro post: apagado, sem mostrar o texto' do
      stub_request(:get, %r{#{ig}/#{comment_id}\?}).to_return(status: 200, headers: json,
                                                              body: comentario.merge(media: { id: '17900000000000999' }).to_json)

      get base, headers: headers, as: :json

      expect(response.parsed_body).to include('status' => 'apagado')
      expect(response.parsed_body).not_to have_key('comentario')
    end

    it 'Meta fora do ar: meta_unavailable' do
      stub_request(:get, %r{#{ig}/#{comment_id}\?}).to_return(status: 500, headers: json, body: { error: { code: 2 } }.to_json)

      get base, headers: headers, as: :json

      expect(response.parsed_body).to include('status' => 'meta_unavailable')
    end

    it 'já apagado pela conta: não chama a Meta' do
      Crm::MetaAdsCommentAction.record!(account: account, network: 'instagram', comment_id: comment_id, action: 'delete', actor: 'user',
                                        user: admin)

      get base, headers: headers, as: :json

      expect(response.parsed_body).to include('status' => 'apagado')
      expect(instagram_call).not_to have_been_made
    end

    it 'sem a flag: 404 sem chamar a Meta' do
      account.disable_features!('meta_ads_comentarios_ia')

      get base, headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
      expect(instagram_call).not_to have_been_made
    end

    it 'conversa que não nasceu de comentário: 404' do
      conversation.update!(additional_attributes: {})

      get base, headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'comentário do Facebook: 404 (fora desta fase)' do
      conversation.update!(additional_attributes: { 'meta_ads_comment' => origem.merge('network' => 'facebook') })

      get base, headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'conversa de outra conta com o mesmo número: 404, sem chamar a Meta' do
      outra = create(:account)
      outra.enable_features!('meta_ads_comentarios_ia')
      admin_da_outra = create(:user, account: outra, role: :administrator)
      conversation # a conversa desta conta existe com este display_id

      get "/api/v1/accounts/#{outra.id}/conversations/#{conversation.display_id}/comentario",
          headers: admin_da_outra.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
      expect(instagram_call).not_to have_been_made
    end

    it 'agente sem acesso à caixa: 401, sem chamar a Meta' do
      agente = create(:user, account: account, role: :agent)

      get base, headers: agente.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(instagram_call).not_to have_been_made
    end
  end

  describe 'responder em público' do
    it 'publica a resposta no comentário, grava atividade, ação e Auditoria sem o texto' do
      reply = stub_request(:post, "#{ig}/#{comment_id}/replies").with(query: hash_including({}), body: { message: 'Te mandei no direct' })
                                                                .to_return(status: 200, headers: json, body: { id: '18000000000000777' }.to_json)

      post "#{base}/responder", params: { content: 'Te mandei no direct' }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('resposta' => { 'texto' => 'Te mandei no direct' })
      expect(reply).to have_been_made.once
      expect(atividades).to include('Ana replied in public on the post: “Te mandei no direct”')
      expect(Crm::MetaAdsCommentAction.find_by(comment_id: '18000000000000777', action: 'page_reply')).to be_present
      audit = Audited.audit_class.find_by(action: 'conversation_comment')
      expect(audit.audited_changes).to eq('network' => 'instagram', 'conversation_id' => conversation.display_id, 'post_id' => post_id,
                                          'comment_id' => comment_id, 'action' => 'reply')
    end

    it 'texto vazio: 422 invalid_text, sem chamar a Meta para responder' do
      post "#{base}/responder", params: { content: '  ' }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq('error' => 'invalid_text')
      expect(a_request(:post, /replies/)).not_to have_been_made
      expect(atividades).to be_empty
    end

    it 'conteúdo que não é texto: 422 invalid_text' do
      post "#{base}/responder", params: { content: { a: 1 } }, headers: headers, as: :json

      expect(response.parsed_body).to eq('error' => 'invalid_text')
    end

    it 'Meta recusa por permissão: 422 needs_permission e nada gravado' do
      stub_request(:post, "#{ig}/#{comment_id}/replies").with(query: hash_including({}))
                                                        .to_return(status: 403, headers: json, body: { error: { code: 10 } }.to_json)

      post "#{base}/responder", params: { content: 'Oi' }, headers: headers, as: :json

      expect(response.parsed_body).to eq('error' => 'needs_permission')
      expect(atividades).to be_empty
      expect(Audited.audit_class.where(action: 'conversation_comment')).to be_empty
    end
  end

  describe 'esconder' do
    it 'esconde e mostra de novo, com atividade e ação' do
      hide = stub_request(:post, %r{#{ig}/#{comment_id}\?}).to_return(status: 200, headers: json, body: { success: true }.to_json)

      post "#{base}/esconder", params: { hidden: true }, headers: headers, as: :json
      expect(response.parsed_body).to eq('escondido' => true)
      post "#{base}/esconder", params: { hidden: false }, headers: headers, as: :json
      expect(response.parsed_body).to eq('escondido' => false)

      expect(hide).to have_been_made.twice
      expect(atividades).to include('Ana hid the comment on the post', 'Ana showed the comment on the post again')
      expect(Crm::MetaAdsCommentAction.where(comment_id: comment_id).pluck(:action)).to contain_exactly('hide', 'show')
    end

    it 'sem hidden ou com valor que não é true/false: 422, sem chamar a Meta para esconder' do
      [nil, 'talvez'].each do |valor|
        post "#{base}/esconder", params: { hidden: valor }, headers: headers, as: :json

        expect(response.parsed_body).to eq('error' => 'invalid_hidden')
      end
      expect(a_request(:post, /graph\.instagram\.com/).with { |r| !r.uri.path.end_with?('subscribed_apps') }).not_to have_been_made
    end
  end

  describe 'apagar' do
    it 'apaga na Meta, grava ação e atividade sem o texto do comentário' do
      apagar = stub_request(:delete, %r{#{ig}/#{comment_id}\?}).to_return(status: 200, headers: json, body: { success: true }.to_json)

      delete base, headers: headers, as: :json

      expect(response.parsed_body).to eq('status' => 'apagado')
      expect(apagar).to have_been_made.once
      expect(atividades).to include('Ana deleted the comment from the post')
      expect(atividades.join).not_to include('Quanto custa?')
      expect(Crm::MetaAdsCommentAction.exists?(comment_id: comment_id, action: 'delete')).to be(true)
    end

    it 'comentário que já não existe na Meta: 404 comment_not_found, sem apagar' do
      stub_request(:get, %r{#{ig}/#{comment_id}\?})
        .to_return(status: 400, headers: json, body: { error: { code: 100, error_subcode: 33 } }.to_json)

      delete base, headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to eq('error' => 'comment_not_found')
      expect(a_request(:delete, /graph\.instagram\.com/)).not_to have_been_made
    end
  end
end
