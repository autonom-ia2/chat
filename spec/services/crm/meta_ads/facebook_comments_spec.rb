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
    stub_request(:get, meta_graph_url(page_id)).with(query: { fields: 'access_token' })
                                               .to_return(status: 200, body: { access_token: page_token }.to_json, headers: json)
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
                          replies: [comment('200000000000002_400', name: 'Loja Exemplo', message: 'Temos sim!', from_id: page_id, can_hide: false)]),
      comment('200000000000002_500', name: nil, message: 'Ainda não chegou.', hidden: true)
    ]
    body = { id: post_id, permalink_url: 'https://www.facebook.com/p/1',
             comments: { data: data, summary: { total_count: total },
                         paging: { cursors: { after: after }, next: after && 'https://graph.facebook.com/next' }.compact } }
    stub_request(:get, meta_graph_url(post_id)).with(query: { fields: Meta::AdsGraphClient::POST_COMMENTS_FIELDS },
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

      result = described_class.new(connection).list(ad_id)

      expect(result).to include(status: 'ready', permalink_url: 'https://www.facebook.com/p/1', total: 2, next_cursor: 'CURSOR1')
      first, second = result[:comments]
      expect(first).to include(id: comment_id, author: { name: 'Mariana Costa', is_page: false }, text: 'Ainda tem no tamanho M?',
                               hidden: false, can_reply: true, can_hide: true, can_delete: true, can_reply_private: false)
      expect(first[:replies].first).to include(author: { name: 'Loja Exemplo', is_page: true }, can_hide: false, can_reply: false)
      expect(second).to include(author: { name: nil, is_page: false }, hidden: true, replies: [])
    end

    it 'sem pages_manage_engagement lê, mas nenhuma linha deixa responder, ocultar ou apagar' do
      ready!('pages_read_user_content')
      stub_comments

      rows = described_class.new(connection).list(ad_id)[:comments]

      expect(rows.flat_map { |row| [row] + row[:replies] }.map { |row| row.values_at(:can_reply, :can_hide, :can_delete) }.flatten.uniq)
        .to eq([false])
    end

    it 'sem pages_read_user_content pede para entrar de novo, sem ler o post' do
      stub_permissions('pages_manage_engagement', 'ads_read')

      expect(described_class.new(connection).list(ad_id)).to eq(status: 'needs_login', comments: [], total: 0, next_cursor: nil)
      expect(a_request(:get, meta_graph_url(post_id))).not_to have_been_made
    end

    it 'modo parceiro pede para entrar com o Facebook (o token é o da plataforma, não o da pessoa)' do
      connection.update!(mode: 'partner', access_token: nil)

      expect(described_class.new(connection).list(ad_id)).to include(status: 'needs_login')
      expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
    end

    it 'anúncio sem post da Página: a aba some (no_post)' do
      stub_permissions(*all_permissions)
      stub_ad(story: nil)

      expect(described_class.new(connection).list(ad_id)).to include(status: 'no_post')
    end

    it 'anúncio de outra conta de anúncios não existe' do
      stub_permissions(*all_permissions)
      stub_ad(account_id: '999')

      expect { described_class.new(connection).list(ad_id) }.to raise_error(described_class::Error, 'ad_not_found')
    end

    it 'sem token da Página (a pessoa não administra a Página do anúncio): pede para entrar de novo' do
      stub_permissions(*all_permissions)
      stub_ad
      stub_request(:get, meta_graph_url(page_id)).with(query: { fields: 'access_token' })
                                                 .to_return(status: 200, body: { id: page_id }.to_json, headers: json)

      expect(described_class.new(connection).list(ad_id)).to include(status: 'needs_login')
    end

    it 'mais comentários pelo cursor' do
      ready!(*all_permissions)
      stub_request(:get, meta_graph_url("#{post_id}/comments"))
        .with(query: hash_including('after' => 'CURSOR1', 'fields' => Meta::AdsGraphClient::COMMENT_FIELDS_WITH_REPLIES))
        .to_return(status: 200, headers: json,
                   body: { data: [comment('200000000000002_600', name: 'Fernanda Lima', message: 'Outras cores?')], paging: {} }.to_json)

      result = described_class.new(connection).more(ad_id, 'CURSOR1')

      expect(result).to match(comments: [hash_including(id: '200000000000002_600', text: 'Outras cores?')], next_cursor: nil)
    end
  end

  describe 'ações' do
    before { ready!(*all_permissions) }

    it 'responde como a Página, embaixo do comentário' do
      reply = stub_request(:post, meta_graph_url("#{comment_id}/comments"))
              .with(body: { message: 'Entregamos sim!' }, headers: { 'Authorization' => "Bearer #{page_token}" })
              .to_return(status: 200, body: { id: '200000000000002_700' }.to_json, headers: json)

      expect(described_class.new(connection).reply!(ad_id, comment_id, '  Entregamos sim!  ')).to eq(id: '200000000000002_700')
      expect(reply).to have_been_requested.once
    end

    it 'oculta e mostra' do
      hide = stub_request(:post, meta_graph_url(comment_id)).with(body: { is_hidden: 'true' })
                                                            .to_return(status: 200, body: { success: true }.to_json, headers: json)

      expect(described_class.new(connection).hide!(ad_id, comment_id, true)).to be(true)
      expect(hide).to have_been_requested.once
    end

    it 'apaga com o token da Página' do
      delete = stub_request(:delete, meta_graph_url(comment_id)).with(headers: { 'Authorization' => "Bearer #{page_token}" })
                                                                .to_return(status: 200, body: { success: true }.to_json, headers: json)

      described_class.new(connection).delete!(ad_id, comment_id)

      expect(delete).to have_been_requested.once
    end

    it 'comentário de outro post (ou id malformado) não chega à Meta' do
      service = described_class.new(connection)

      ['999_300', '300', "#{comment_id}/likes", '200000000000002_3?method=delete', '', nil].each do |bad|
        expect { service.hide!(ad_id, bad, true) }.to raise_error(described_class::Error, 'comment_not_found')
      end
      expect(a_request(:post, /graph\.facebook\.com/)).not_to have_been_made
    end

    it 'texto vazio ou longo demais não vai' do
      service = described_class.new(connection)

      expect { service.reply!(ad_id, comment_id, '   ') }.to raise_error(described_class::Error, 'invalid_message')
      expect { service.reply!(ad_id, comment_id, 'a' * 8001) }.to raise_error(described_class::Error, 'invalid_message')
    end

    it 'sem pages_manage_engagement não age' do
      WebMock.reset!
      ready!('pages_read_user_content')

      expect { described_class.new(connection).delete!(ad_id, comment_id) }.to raise_error(described_class::Error, 'needs_login')
      expect(a_request(:delete, /graph\.facebook\.com/)).not_to have_been_made
    end

    it 'recusa da Meta vira meta_refused; falha passageira, meta_unavailable' do
      allow(Rails.logger).to receive(:warn)
      stub_request(:delete, meta_graph_url(comment_id)).to_return(status: 400, body: meta_graph_error(100).to_json, headers: json)
      expect { described_class.new(connection).delete!(ad_id, comment_id) }.to raise_error(described_class::Error, 'meta_refused')

      stub_request(:delete, meta_graph_url(comment_id)).to_return(status: 500, body: meta_graph_error(1).to_json, headers: json)
      expect { described_class.new(connection).delete!(ad_id, comment_id) }.to raise_error(described_class::Error, 'meta_unavailable')
    end
  end
end
