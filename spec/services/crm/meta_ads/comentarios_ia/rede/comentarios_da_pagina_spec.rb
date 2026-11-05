require 'rails_helper'

# #2587: o motor do Facebook lê, responde e esconde com o token da caixa da Página (Channel::FacebookPage), em post e em
# anúncio, sem a conexão de Anúncios. Mesma interface que o Rede::Facebook usava do Crm::MetaAds::FacebookComments.
RSpec.describe Crm::MetaAds::ComentariosIa::Rede::ComentariosDaPagina do
  let(:account) { create(:account) }
  let(:page_id) { '555' }
  let(:canal) { create(:channel_facebook_page, account: account, page_id: page_id) }
  let(:post_id) { "#{page_id}_200000000000002" }
  let(:comment_id) { '200000000000002_300000000000003' }
  let(:leitor) { described_class.new(canal) }
  let(:json) { { 'Content-Type' => 'application/json' } }
  let(:erro) { Crm::MetaAds::FacebookComments::Error }

  def com_token
    { headers: { 'Authorization' => "Bearer #{canal.page_access_token}" } }
  end

  def comentario_na_meta(status: 200, body: { id: comment_id, message: 'Quanto custa?', from: { id: '77', name: 'Ana' } })
    stub_request(:get, meta_graph_url(comment_id)).with(query: { fields: Meta::AdsGraphClient::PageComments::COMMENT_FIELDS }, **com_token)
                                                  .to_return(status: status, body: body.to_json, headers: json)
  end

  describe '#comment' do
    it 'lê o comentário com o token da caixa, sem conexão de Anúncios na conta' do
      comentario_na_meta

      expect(leitor.comment(post_id, comment_id)).to include('message' => 'Quanto custa?', 'from' => { 'id' => '77', 'name' => 'Ana' })
      expect(Crm::MetaAdsConnection.where(account_id: account.id)).not_to exist
    end

    it 'comentário de outro post, ou post de outra Página: comment_not_found, sem chamar a Meta' do
      expect { leitor.comment(post_id, '999_1') }.to raise_error(erro) { |e| expect(e.code).to eq('comment_not_found') }
      expect { leitor.comment('666_200000000000002', comment_id) }.to raise_error(erro) { |e| expect(e.code).to eq('comment_not_found') }
      expect(a_request(:get, meta_graph_url('999_1')).with(query: hash_including({}))).not_to have_been_made
      expect(a_request(:get, meta_graph_url(comment_id)).with(query: hash_including({}))).not_to have_been_made
    end

    it 'Meta fora do ar: meta_unavailable; outra recusa: meta_refused' do
      comentario_na_meta(status: 503, body: { error: { message: 'fora' } })
      expect { leitor.comment(post_id, comment_id) }.to raise_error(erro) { |e| expect(e.code).to eq('meta_unavailable') }

      comentario_na_meta(status: 400, body: meta_graph_error(100, subcode: 33))
      expect { leitor.comment(post_id, comment_id) }.to raise_error(erro) { |e| expect(e.code).to eq('meta_refused') }
    end

    it 'token da caixa sem permissão ou caído: needs_login' do
      comentario_na_meta(status: 403, body: meta_graph_error(10))
      expect { leitor.comment(post_id, comment_id) }.to raise_error(erro) { |e| expect(e.code).to eq('needs_login') }

      comentario_na_meta(status: 400, body: meta_graph_error(190))
      expect { leitor.comment(post_id, comment_id) }.to raise_error(erro) { |e| expect(e.code).to eq('needs_login') }
    end
  end

  it '#post_message e #post_media: o texto e as imagens do post da Página' do
    stub_request(:get, meta_graph_url(post_id)).with(query: { fields: 'message' }, **com_token)
                                               .to_return(status: 200, body: { message: 'Bolo de cenoura' }.to_json, headers: json)
    campos = { fields: 'full_picture,attachments{media,subattachments{media}}' }
    stub_request(:get, meta_graph_url(post_id)).with(query: campos, **com_token)
                                               .to_return(status: 200, body: { full_picture: 'https://cdn.exemplo/bolo.jpg' }.to_json, headers: json)

    expect(leitor.post_message(post_id)).to eq('Bolo de cenoura')
    expect(leitor.post_media(post_id)).to eq('full_picture' => 'https://cdn.exemplo/bolo.jpg')
  end

  # #2454: a leitura da foto roda dentro da requisição; o prazo vale para cada ida à Graph.
  it 'com prazo: o cliente da Graph recebe o prazo de quem chama' do
    allow(Meta::AdsGraphClient).to receive(:new).and_call_original
    prazo = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3
    stub_request(:get, meta_graph_url(post_id)).with(query: hash_including({})).to_return(status: 200, body: {}.to_json, headers: json)

    described_class.new(canal, prazo: prazo).post_media(post_id)

    expect(Meta::AdsGraphClient).to have_received(:new).with(access_token: canal.page_access_token, prazo: prazo)
  end

  it '#post_message de post de outra Página: nil, sem chamar a Meta' do
    expect(leitor.post_message('666_1')).to be_nil
    expect(a_request(:get, meta_graph_url('666_1')).with(query: hash_including({}))).not_to have_been_made
  end

  describe 'responder e esconder como a IA' do
    it 'responde como a Página e grava a ação como ai, na conta da caixa' do
      stub_request(:post, meta_graph_url("#{comment_id}/comments")).with(**com_token)
                                                                   .to_return(status: 200, body: { id: '200000000000002_9' }.to_json, headers: json)

      expect(leitor.reply_as_ai(post_id, comment_id, '  Te chamei no privado  ')).to eq(id: '200000000000002_9')
      resposta = a_request(:post, meta_graph_url("#{comment_id}/comments")).with(body: hash_including('message' => 'Te chamei no privado'))
      expect(resposta).to have_been_made
      expect(Crm::MetaAdsCommentAction.sole).to have_attributes(account_id: account.id, network: 'facebook', comment_id: comment_id,
                                                                action: 'reply', actor: 'ai', ad_id: nil, user_id: nil)
    end

    it 'esconde e grava; texto vazio é invalid_text sem chamar a Meta' do
      stub_request(:post, meta_graph_url(comment_id)).with(**com_token).to_return(status: 200, body: { success: true }.to_json, headers: json)

      expect(leitor.hide_as_ai(post_id, comment_id, true)).to be(true)
      expect(Crm::MetaAdsCommentAction.sole).to have_attributes(action: 'hide', actor: 'ai')
      expect { leitor.reply_as_ai(post_id, comment_id, '  ') }.to raise_error(erro) { |e| expect(e.code).to eq('invalid_text') }
    end

    it 'recusa da Meta não grava a ação' do
      stub_request(:post, meta_graph_url(comment_id)).with(**com_token).to_return(status: 403, body: meta_graph_error(10).to_json, headers: json)

      expect { leitor.hide_as_ai(post_id, comment_id, true) }.to raise_error(erro) { |e| expect(e.code).to eq('needs_login') }
      expect(Crm::MetaAdsCommentAction.count).to eq(0)
    end
  end

  # A ponta: o adaptador do motor (Rede.para), com a caixa de verdade, numa conta sem conexão de Anúncios. Vale para o
  # post da Página e para o post por trás de um anúncio (o evento do Facebook chega sem ad_id).
  describe 'pelo Rede::Facebook, sem conexão de Anúncios' do
    let(:evento) do
      Crm::MetaAds::ComentariosIa::Comentario.new(
        network: 'facebook', account_id: account.id, inbox_id: canal.inbox.id, owner_id: page_id, post_id: post_id, ad_id: nil,
        comment_id: comment_id, parent_id: nil, from_id: '77', from_name: 'Ana', text: nil, created_time: Time.current
      )
    end
    let(:rede) { Crm::MetaAds::ComentariosIa::Rede.para(canal.inbox, evento) }

    it 'lê, responde e esconde pela caixa' do
      comentario_na_meta
      stub_request(:post, meta_graph_url("#{comment_id}/comments")).with(**com_token)
                                                                   .to_return(status: 200, body: { id: '200000000000002_9' }.to_json, headers: json)
      stub_request(:post, meta_graph_url(comment_id)).with(**com_token).to_return(status: 200, body: { success: true }.to_json, headers: json)

      expect(rede.ler).to eq(text: 'Quanto custa?', from_name: 'Ana', from_id: '77')
      expect(rede.responder('Te chamei')).to be(true)
      expect(rede.esconder).to be(true)
      expect(Crm::MetaAdsCommentAction.where(account_id: account.id, actor: 'ai').pluck(:action)).to contain_exactly('reply', 'hide')
    end

    it 'token da caixa sem permissão: Indisponivel (o job tenta de novo e, esgotado, deixa com o dono)' do
      comentario_na_meta(status: 403, body: meta_graph_error(10))

      expect { rede.ler }.to raise_error(Crm::MetaAds::ComentariosIa::Rede::Indisponivel)
    end
  end
end
