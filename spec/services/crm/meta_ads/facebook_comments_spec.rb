require 'rails_helper'

# Comentários do post do anúncio no Facebook (#2197): lidos e moderados com o token da Página, só no post do
# anúncio da conta da conexão; sem pages_read_user_content a aba pede para entrar de novo; sem
# pages_manage_engagement lê mas não age.
RSpec.describe Crm::MetaAds::FacebookComments do
  let(:account) { create(:account) }
  let(:connection) { create_meta_ads_insights_connection(account) }
  let(:ad_id) { '120254710382770416' }
  let(:page_id) { '100000000000001' }
  let(:post_id) { "#{page_id}_200000000000002" }
  let(:comment_id) { '200000000000002_300000000000003' }
  let(:page_token) { 'PAGETOKEN123' }
  let(:json) { { 'Content-Type' => 'application/json' } }
  let(:all_permissions) { %w[pages_read_user_content pages_manage_engagement] }

  let!(:page_record) { simulate_meta_ads_comment_pieces(account: account, page_id: page_id) }
  # A caixa do Messenger da Página (#2359): quem lê ou age precisa vê-la (InboxPolicy#show?, aqui `inbox_access`).
  let!(:page_inbox) { create(:inbox, account: account, channel: build(:channel_facebook_page, account: account, page_id: page_id)) }
  let(:inbox_access) { ->(inbox) { inbox == page_inbox } }

  def build_service(**)
    described_class.new(connection, inbox_access: inbox_access, **)
  end

  def stub_permissions(*granted)
    stub_request(:get, meta_graph_url('me/permissions'))
      .to_return(status: 200, body: { data: granted.map { |name| { permission: name, status: 'granted' } } }.to_json, headers: json)
  end

  def stub_ad(account_id: connection.ad_account_id, story: post_id)
    stub_request(:get, meta_graph_url(ad_id)).with(query: { fields: Meta::AdsGraphClient::AD_MANAGEMENT_FIELDS })
                                             .to_return(status: 200, headers: json,
                                                        body: { id: ad_id, account_id: account_id, status: 'ACTIVE', effective_status: 'ACTIVE',
                                                                creative: { id: '9', effective_object_story_id: story }.compact }.to_json)
  end

  def stub_page_token
    stub_request(:get, meta_graph_url(page_id)).with(query: { fields: 'access_token,name' })
                                               .to_return(status: 200, body: { access_token: page_token, name: 'Loja Exemplo' }.to_json,
                                                          headers: json)
  end

  def comment(id, name:, message:, **opts)
    opts = { from_id: '555', hidden: false, can_hide: true, replies: nil }.merge(opts)
    {
      id: id, from: name ? { id: opts[:from_id], name: name } : nil, message: message, created_time: '2026-10-27T12:00:00+0000',
      is_hidden: opts[:hidden], can_hide: opts[:can_hide], can_remove: true, can_comment: true,
      comments: opts[:replies] && { data: opts[:replies] }
    }.compact
  end

  def stub_comments(data: nil, after: nil, total: 2)
    data ||= [
      comment(comment_id, name: 'Mariana Costa', message: 'Ainda tem no tamanho M?',
                          replies: [comment('200000000000002_400', name: 'Loja Exemplo', message: 'Temos sim!', from_id: page_id, can_hide: false),
                                    comment('200000000000002_450', name: 'Ana', message: 'Eu também quero')]),
      comment('200000000000002_500', name: nil, message: 'Ainda não chegou.', hidden: true)
    ]
    body = { id: post_id, permalink_url: 'https://www.facebook.com/p/1',
             comments: { data: data, summary: { total_count: total },
                         paging: { cursors: { after: after }, next: after && 'https://graph.facebook.com/next' }.compact } }
    stub_request(:get, meta_graph_url(post_id)).with(query: { fields: Meta::AdsGraphClient::PageComments::POST_COMMENTS_FIELDS },
                                                     headers: { 'Authorization' => "Bearer #{page_token}" })
                                               .to_return(status: 200, body: body.to_json, headers: json)
  end

  def ready!(*permissions)
    stub_permissions(*permissions)
    stub_ad
    stub_page_token
  end

  describe '#list' do
    it 'traz os comentários do post do anúncio, com uma camada de respostas, quem é a Página e o que dá para fazer' do
      ready!(*all_permissions)
      stub_comments(after: 'CURSOR1')

      result = build_service.list(ad_id)

      expect(result).to include(status: 'ready', permalink_url: 'https://www.facebook.com/p/1', total: 2, next_cursor: 'CURSOR1')
      first, second = result[:comments]
      expect(first).to include(id: comment_id, author: { name: 'Mariana Costa', is_page: false }, text: 'Ainda tem no tamanho M?',
                               hidden: false, can_reply: true, can_hide: true, can_delete: true, can_reply_private: false)
      expect(first[:replies].first).to include(author: { name: 'Loja Exemplo', is_page: true }, can_hide: false, can_reply: false)
      # Provisório até a chamada real: resposta sem botões, mesmo de cliente e com a Meta deixando.
      expect(first[:replies].last).to include(author: { name: 'Ana', is_page: false }, can_reply: false, can_hide: false, can_delete: false)
      expect(second).to include(author: { name: nil, is_page: false }, hidden: true, replies: [])
    end

    it 'comentário só com foto vem com o tipo do anexo, sem texto' do
      ready!(*all_permissions)
      stub_comments(data: [comment(comment_id, name: 'Ana', message: nil).merge(attachment: { type: 'photo' })], total: nil)

      result = build_service.list(ad_id)

      expect(result[:comments].first).to include(text: nil, attachment: 'photo')
      expect(result[:total]).to be_nil
    end

    it 'post apagado (a Meta não acha mais): a aba some, em vez de erro para sempre' do
      ready!(*all_permissions)
      stub_request(:get, meta_graph_url(post_id)).with(query: hash_including({}))
                                                 .to_return(status: 400, body: meta_graph_error(100, subcode: 33).to_json, headers: json)
      allow(Rails.logger).to receive(:warn)

      expect(build_service.list(ad_id)).to include(status: 'no_post', comments: [])
    end

    it 'sem pages_manage_engagement lê, mas nenhuma linha deixa responder, ocultar ou apagar' do
      ready!('pages_read_user_content')
      stub_comments

      rows = build_service.list(ad_id)[:comments]

      expect(rows.flat_map { |row| [row] + row[:replies] }.map { |row| row.values_at(:can_reply, :can_hide, :can_delete) }.flatten.uniq)
        .to eq([false])
    end

    it 'sem pages_read_user_content pede para entrar de novo, sem ler o post' do
      stub_permissions('pages_manage_engagement', 'ads_read')
      stub_ad

      expect(build_service.list(ad_id)).to eq(status: 'needs_login', comments: [], total: 0, next_cursor: nil)
      expect(a_request(:get, meta_graph_url(post_id))).not_to have_been_made
    end

    it 'modo parceiro pede para entrar com o Facebook (o token é o da plataforma, não o da pessoa)' do
      connection.update!(mode: 'partner', access_token: nil)

      expect(build_service.list(ad_id)).to include(status: 'needs_login')
      expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
    end

    it 'anúncio sem post da Página: a aba some (no_post)' do
      stub_permissions(*all_permissions)
      stub_ad(story: nil)

      expect(build_service.list(ad_id)).to include(status: 'no_post')
    end

    it 'anúncio de outra conta de anúncios não existe' do
      stub_permissions(*all_permissions)
      stub_ad(account_id: '999')

      expect { build_service.list(ad_id) }.to raise_error(described_class::Error, 'ad_not_found')
    end

    it 'sem token da Página (a Página não foi escolhida no login ou a pessoa não a administra): pede para entrar de novo' do
      stub_permissions(*all_permissions)
      stub_ad
      stub_request(:get, meta_graph_url(page_id)).with(query: { fields: 'access_token,name' })
                                                 .to_return(status: 200, body: { id: page_id }.to_json, headers: json)

      expect(build_service.list(ad_id)).to include(status: 'needs_login')
    end

    it 'Página que a Meta recusa por outro motivo (sumiu, id inválido) é meta_refused: entrar de novo não resolve' do
      stub_permissions(*all_permissions)
      stub_ad
      stub_request(:get, meta_graph_url(page_id)).with(query: { fields: 'access_token,name' })
                                                 .to_return(status: 400, body: meta_graph_error(100).to_json, headers: json)
      allow(Rails.logger).to receive(:warn)

      expect { build_service.list(ad_id) }.to raise_error(described_class::Error, 'meta_refused')
    end

    it 'falha passageira ao conferir permissão é meta_unavailable, não pedido de entrar de novo' do
      stub_request(:get, meta_graph_url('me/permissions')).to_return(status: 500, body: meta_graph_error(1).to_json, headers: json)
      stub_ad
      allow(Rails.logger).to receive(:warn)

      expect { build_service.list(ad_id) }.to raise_error(described_class::Error, 'meta_unavailable')
    end

    it 'quem pode gerir: guarda a Página e assina o feed dela uma vez' do
      page_record.update!(feed_receiving: false)
      subscription = instance_double(Crm::MetaAds::PageSubscription, add!: true)
      allow(Crm::MetaAds::PageSubscription).to receive(:new).and_return(subscription)
      ready!(*all_permissions)
      stub_comments

      build_service(can_manage: true).list(ad_id)
      build_service(can_manage: true).list(ad_id)

      expect(page_record.reload).to have_attributes(name: 'Loja Exemplo', feed_receiving: true)
      expect(Crm::MetaAds::PageSubscription).to have_received(:new)
        .with(page_id: page_id, access_token: page_token).once
      expect(subscription).to have_received(:add!).with(%w[feed]).once
    end

    # #2359: leitura não escreve. Quem só vê lê os comentários sem gravar a Página nem assinar o feed dela.
    it 'quem só vê: lê sem guardar a Página nem assinar o feed' do
      page_record.destroy!
      ready!(*all_permissions)
      stub_comments

      expect(build_service.list(ad_id)).to include(status: 'ready')
      expect(Crm::MetaAdsPage.where(account_id: account.id)).to be_empty
      expect(Crm::MetaAds::PageSubscription).not_to have_received(:new).with(page_id: page_id, access_token: page_token)
    end

    it 'mais comentários sem permissão: mesmo estado da primeira página' do
      stub_permissions('ads_read')
      stub_ad

      expect(build_service.more(ad_id, 'CURSOR1')).to include(status: 'needs_login', comments: [])
    end

    it 'mais comentários pelo cursor' do
      ready!(*all_permissions)
      stub_request(:get, meta_graph_url("#{post_id}/comments"))
        .with(query: hash_including('after' => 'CURSOR1', 'fields' => Meta::AdsGraphClient::PageComments::COMMENT_FIELDS_WITH_REPLIES))
        .to_return(status: 200, headers: json,
                   body: { data: [comment('200000000000002_600', name: 'Fernanda Lima', message: 'Outras cores?')], paging: {} }.to_json)

      page_record.destroy!

      result = build_service(can_manage: true).more(ad_id, 'CURSOR1')

      expect(result).to match(status: 'ready', comments: [hash_including(id: '200000000000002_600', text: 'Outras cores?')],
                              next_cursor: nil)
      # #2359: a página seguinte nunca grava nada, nem para quem pode gerir (a primeira já guardou).
      expect(Crm::MetaAdsPage.where(account_id: account.id)).to be_empty
      expect(Crm::MetaAds::PageSubscription).not_to have_received(:new).with(page_id: page_id, access_token: page_token)
    end
  end

  # #2359 (decisão A do Rodrigo): ler e agir pedem ver a caixa do Messenger da Página. Sem caixa, ninguém lê, nem o
  # administrador; com caixa e sem ser dela, também não. Em nenhum dos dois casos a Página é lida na Meta.
  describe 'caixa do Messenger da Página' do
    it 'com caixa e quem vê a caixa: lê' do
      ready!(*all_permissions)
      stub_comments

      expect(build_service.list(ad_id)).to include(status: 'ready')
    end

    it 'com caixa e quem não vê a caixa: not_inbox_member, sem ler a Página nem agir' do
      ready!(*all_permissions)
      service = described_class.new(connection, inbox_access: ->(_inbox) { false }, can_manage: true)

      expect(service.list(ad_id)).to eq(status: 'not_inbox_member', comments: [], total: 0, next_cursor: nil)
      expect(service.more(ad_id, 'CURSOR1')).to include(status: 'not_inbox_member', comments: [])
      expect { service.delete!(ad_id, comment_id) }.to raise_error(described_class::Error, 'not_inbox_member')
      expect(a_request(:get, meta_graph_url(page_id)).with(query: hash_including({}))).not_to have_been_made
      expect(a_request(:any, /#{post_id}|#{comment_id}/o)).not_to have_been_made
    end

    it 'sem caixa da Página na conta: no_inbox para todos, sem ler a Página nem agir' do
      Channel::FacebookPage.where(id: page_inbox.channel_id).delete_all
      ready!(*all_permissions)
      service = described_class.new(connection, inbox_access: ->(_inbox) { true }, can_manage: true)

      expect(service.list(ad_id)).to eq(status: 'no_inbox', comments: [], total: 0, next_cursor: nil)
      expect { service.hide!(ad_id, comment_id, true) }.to raise_error(described_class::Error, 'no_inbox')
      expect(a_request(:get, meta_graph_url(page_id)).with(query: hash_including({}))).not_to have_been_made
    end

    it 'sem caixa, o motivo é a caixa mesmo sem a permissão de leitura, e as permissões nem são conferidas' do
      Channel::FacebookPage.where(id: page_inbox.channel_id).delete_all
      stub_permissions('ads_read')
      stub_ad

      expect(build_service.list(ad_id)).to include(status: 'no_inbox')
      expect(a_request(:get, meta_graph_url('me/permissions'))).not_to have_been_made
    end

    it 'caixa do Messenger de outra Página não conta' do
      page_inbox.channel.update!(page_id: '999999999999999')
      ready!(*all_permissions)

      expect(described_class.new(connection, inbox_access: ->(_inbox) { true }).list(ad_id)).to include(status: 'no_inbox')
    end
  end

  describe 'ações' do
    before { ready!(*all_permissions) }

    it 'responde como a Página, embaixo do comentário' do
      reply = stub_request(:post, meta_graph_url("#{comment_id}/comments"))
              .with(body: { message: 'Entregamos sim!' }, headers: { 'Authorization' => "Bearer #{page_token}" })
              .to_return(status: 200, body: { id: '200000000000002_700' }.to_json, headers: json)

      user = create(:user)
      expect(build_service.reply!(ad_id, comment_id, '  Entregamos sim!  ', user: user)).to eq(id: '200000000000002_700')
      expect(reply).to have_been_requested.once
      expect(Crm::MetaAdsCommentAction.sole).to have_attributes(account_id: account.id, network: 'facebook', ad_id: ad_id,
                                                                comment_id: comment_id, action: 'reply', actor: 'user', user_id: user.id)
    end

    it 'oculta e mostra' do
      hide = stub_request(:post, meta_graph_url(comment_id)).with(body: { is_hidden: 'true' })
                                                            .to_return(status: 200, body: { success: true }.to_json, headers: json)

      expect(build_service.hide!(ad_id, comment_id, true)).to be(true)
      expect(hide).to have_been_requested.once
    end

    it 'apaga com o token da Página' do
      delete = stub_request(:delete, meta_graph_url(comment_id)).with(headers: { 'Authorization' => "Bearer #{page_token}" })
                                                                .to_return(status: 200, body: { success: true }.to_json, headers: json)

      build_service.delete!(ad_id, comment_id)

      expect(delete).to have_been_requested.once
    end

    it 'comentário de outro post (ou id malformado) não chega à Meta' do
      service = build_service

      ['999_300', '300', "#{comment_id}/likes", '200000000000002_3?method=delete', '', nil].each do |bad|
        expect { service.hide!(ad_id, bad, true) }.to raise_error(described_class::Error, 'comment_not_found')
      end
      expect(a_request(:post, /graph\.facebook\.com/)).not_to have_been_made
    end

    it 'texto vazio ou longo demais não vai' do
      service = build_service

      expect { service.reply!(ad_id, comment_id, '   ') }.to raise_error(described_class::Error, 'invalid_text')
      expect { service.reply!(ad_id, comment_id, 'a' * 8001) }.to raise_error(described_class::Error, 'invalid_text')
    end

    it 'sem pages_manage_engagement não age' do
      WebMock.reset!
      ready!('pages_read_user_content')

      expect { build_service.delete!(ad_id, comment_id) }.to raise_error(described_class::Error, 'needs_login')
      expect(a_request(:delete, /graph\.facebook\.com/)).not_to have_been_made
    end

    it 'recusa da Meta vira meta_refused; falha passageira, meta_unavailable' do
      allow(Rails.logger).to receive(:warn)
      stub_request(:delete, meta_graph_url(comment_id)).to_return(status: 400, body: meta_graph_error(100).to_json, headers: json)
      expect { build_service.delete!(ad_id, comment_id) }.to raise_error(described_class::Error, 'meta_refused')

      stub_request(:delete, meta_graph_url(comment_id)).to_return(status: 500, body: meta_graph_error(1).to_json, headers: json)
      expect { build_service.delete!(ad_id, comment_id) }.to raise_error(described_class::Error, 'meta_unavailable')
    end

    # #2212: a IA age pelo post do comentário que chegou pelo evento, sem pessoa e sem anúncio.
    it 'pela IA: responde e oculta pelo post, gravando o actor, sem pessoa nem anúncio' do
      stub_request(:post, meta_graph_url("#{comment_id}/comments")).with(body: { message: 'Te chamei no Messenger' })
                                                                   .to_return(status: 200, body: { id: '200000000000002_800' }.to_json, headers: json)
      stub_request(:post, meta_graph_url(comment_id)).with(body: { is_hidden: 'true' })
                                                     .to_return(status: 200, body: { success: true }.to_json, headers: json)
      service = described_class.new(connection, inbox_access: ->(_inbox) { true })
      ia = { actor: 'ai', user: nil, ad_id: nil }

      expect(service.reply_to(post_id, comment_id, 'Te chamei no Messenger', ia)).to eq(id: '200000000000002_800')
      expect(service.hide_in(post_id, comment_id, true, ia)).to be(true)
      expect(Crm::MetaAdsCommentAction.order(:id).pluck(:action, :actor, :ad_id, :user_id))
        .to eq([['reply', 'ai', nil, nil], ['hide', 'ai', nil, nil]])
    end

    it 'pela IA, sem a caixa do Messenger da Página na conta: no_inbox, sem chamar a Meta' do
      Channel::FacebookPage.where(id: page_inbox.channel_id).delete_all
      service = described_class.new(connection, inbox_access: ->(_inbox) { true })
      ia = { actor: 'ai', user: nil, ad_id: nil }

      expect { service.hide_in(post_id, comment_id, true, ia) }.to raise_error(described_class::Error, 'no_inbox')
      expect(a_request(:post, /graph\.facebook\.com/)).not_to have_been_made
    end

    it 'falha ao gravar a ação não desfaz o que a Meta já fez' do
      stub_request(:delete, meta_graph_url(comment_id)).to_return(status: 200, body: { success: true }.to_json, headers: json)
      allow(Crm::MetaAdsCommentAction).to receive(:record!).and_raise(ActiveRecord::RecordInvalid)
      tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
      allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)

      expect(build_service.delete!(ad_id, comment_id)).to be(true)
      expect(tracker).to have_received(:capture_exception)
    end
  end

  describe '#comment (quem consome meta_ads.comment_received, que leva só ids)' do
    before do
      stub_permissions(*all_permissions)
      stub_page_token
    end

    it 'lê o comentário com o token da Página, sem registrar a Página de novo' do
      stub_request(:get, meta_graph_url(comment_id)).with(query: hash_including({}), headers: { 'Authorization' => "Bearer #{page_token}" })
                                                    .to_return(status: 200, headers: json,
                                                               body: { id: comment_id, from: { id: '555', name: 'Ana' }, message: 'Oi' }.to_json)
      allow(Crm::MetaAdsPage).to receive(:remember!)

      expect(build_service.comment(post_id, comment_id)).to include('message' => 'Oi')
      expect(Crm::MetaAdsPage).not_to have_received(:remember!)
    end

    it 'comentário de outro post: nil, com o motivo no log só com ids, sem chamar a Meta pelo comentário' do
      allow(Rails.logger).to receive(:warn)

      expect(build_service.comment(post_id, '999_1')).to be_nil
      expect(Rails.logger).to have_received(:warn).with(include('comment_not_found', '999_1'))
      expect(a_request(:get, meta_graph_url('999_1'))).not_to have_been_made
    end

    it 'Página de outra conta: nil, sem chamar a Meta pelo comentário' do
      allow(Crm::MetaAdsPage).to receive(:account_ids_for).and_return([account.id + 1])

      expect(build_service.comment(post_id, comment_id)).to be_nil
      expect(a_request(:get, meta_graph_url(comment_id))).not_to have_been_made
    end
  end
end
