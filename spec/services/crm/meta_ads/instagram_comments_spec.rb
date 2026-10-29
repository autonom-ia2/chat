require 'rails_helper'

# Comentários do anúncio no Instagram (#2196): o anúncio leva à mídia e ao Instagram dele pelo criativo; a caixa do
# Instagram da conta lê e age pela Graph do login do Instagram. Cada ação confere que o comentário é da mídia do
# anúncio. A resposta no privado vai uma vez só, até 7 dias depois do comentário, e abre a conversa na caixa.
RSpec.describe Crm::MetaAds::InstagramComments do
  subject(:service) { described_class.new(connection, inbox_access: ->(_inbox) { true }, can_manage: true) }

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:connection) { create_meta_ads_insights_connection(account) }
  let(:ad_id) { '120254710382770416' }
  let(:media_id) { '17900000000000001' }
  let(:ig_id) { '17841400000000001' }
  let!(:channel) { create(:channel_instagram, account: account, instagram_id: ig_id, provider_name: 'lojaexemplo') }
  let(:ig) { 'https://graph.instagram.com/v22.0' }
  let(:json) { { 'Content-Type' => 'application/json' } }

  def stub_ad(creative: { effective_instagram_media_id: media_id, instagram_user_id: ig_id,
                          instagram_permalink_url: 'https://www.instagram.com/p/abc/' }, ad_account: '2196424464528988')
    stub_request(:get, meta_graph_url(ad_id)).with(query: hash_including({}))
                                             .to_return(status: 200, headers: json,
                                                        body: { id: ad_id, account_id: ad_account, creative: creative }.to_json)
  end

  def stub_comments(body: nil, status: 200)
    body ||= {
      data: [
        { id: 'c1', text: 'Tem M?', timestamp: 1.hour.ago.iso8601, hidden: false, from: { id: '501', username: 'carla.dias' },
          replies: { data: [{ id: 'c1r', text: 'Temos!', timestamp: 30.minutes.ago.iso8601, hidden: false,
                              from: { id: ig_id, username: 'lojaexemplo' } }] } },
        { id: 'c2', text: 'Loja física?', timestamp: 9.days.ago.iso8601, hidden: true, from: { id: '502', username: 'isa.lima' } }
      ],
      paging: { cursors: { after: 'C2' }, next: 'https://graph.instagram.com/next' }
    }
    stub_request(:get, %r{#{ig}/#{media_id}/comments}).to_return(status: status, headers: json, body: body.to_json)
    stub_request(:get, %r{#{ig}/#{media_id}\?}).to_return(status: 200, headers: json, body: { comments_count: 3 }.to_json)
  end

  # A criação da caixa pela factory inscreve o app (subscribed_apps): não é chamada dos comentários.
  def instagram_call
    a_request(:any, /graph\.instagram\.com/).with { |request| !request.uri.path.end_with?('subscribed_apps') }
  end

  def stub_comment(id, media: media_id, from: '501', timestamp: 1.hour.ago, parent_id: nil)
    stub_request(:get, %r{#{ig}/#{id}\?}).to_return(
      status: 200, headers: json,
      body: { id: id, timestamp: timestamp.iso8601, from: { id: from, username: 'carla.dias' }, media: { id: media },
              parent_id: parent_id }.compact.to_json
    )
  end

  describe '#payload' do
    it 'devolve os comentários prontos para a tela, com o que cada um permite' do
      stub_ad
      stub_comments

      result = service.payload(ad_id)

      expect(result).to include(status: 'ready', permalink_url: 'https://www.instagram.com/p/abc/', total: 3, next_cursor: 'C2',
                                account: { username: 'lojaexemplo', name: channel.inbox.name })
      first, second = result[:comments]
      expect(first).to include(id: 'c1', text: 'Tem M?', hidden: false, can_reply: true, can_hide: true, can_delete: true,
                               can_reply_private: true, private_reply_expired: false,
                               private_reply: nil)
      expect(first[:author]).to eq(name: nil, username: 'carla.dias', is_page: false)
      expect(first[:replies].first).to include(id: 'c1r', can_reply: false, can_hide: false, can_reply_private: false)
      expect(first[:replies].first[:author]).to include(is_page: true)
      expect(second).to include(hidden: true, can_reply_private: false, private_reply_expired: true)
    end

    # Formato visto em produção (#2313): a Graph devolve a resposta da conta em primeiro nível, com `from`, e dentro do
    # comentário, sem `from`.
    it 'resposta da própria conta aparece uma vez só, dentro do comentário, como da conta e só com apagar' do
      stub_ad
      stub_comments(body: {
                      data: [
                        { id: 'r1', text: 'Obrigado!', timestamp: 5.minutes.ago.iso8601, from: { id: ig_id, username: 'lojaexemplo' } },
                        { id: 'c1', text: 'Muito bom!', timestamp: 1.hour.ago.iso8601, from: { id: '501', username: 'carla.dias' },
                          replies: { data: [{ id: 'r1', text: 'Obrigado!', timestamp: 5.minutes.ago.iso8601, parent_id: 'c1' }] } }
                      ]
                    })

      comments = service.payload(ad_id)[:comments]

      expect(comments.pluck(:id)).to eq(['c1'])
      reply = comments.first[:replies].sole
      expect(reply).to include(id: 'r1', can_reply: false, can_hide: false, can_delete: true, can_reply_private: false)
      expect(reply[:author]).to eq(name: nil, username: 'lojaexemplo', is_page: true)
    end

    it 'resposta de outra pessoa sem from continua sem autor e com as ações' do
      stub_ad
      stub_comments(body: {
                      data: [{ id: 'c1', text: 'Muito bom!', timestamp: 1.hour.ago.iso8601, from: { id: '501', username: 'carla.dias' },
                               replies: { data: [{ id: 'r2', text: 'Também achei', timestamp: 5.minutes.ago.iso8601 }] } }]
                    })

      reply = service.payload(ad_id)[:comments].sole[:replies].sole

      expect(reply[:author]).to eq(name: nil, username: nil, is_page: false)
      expect(reply).to include(can_reply: true, can_hide: true)
    end

    it 'cópia de cima com o comentário pai em outra página: fica em cima, como da conta; lá, a gravada pelo painel é da conta' do
      stub_ad
      stub_comments(body: { data: [{ id: 'r1', text: 'Obrigado!', timestamp: 5.minutes.ago.iso8601, parent_id: 'c9',
                                     from: { id: ig_id, username: 'lojaexemplo' } }] })
      alone = service.payload(ad_id)[:comments].sole
      expect(alone).to include(id: 'r1', can_reply_private: false)
      expect(alone[:author]).to include(username: 'lojaexemplo', is_page: true)

      Crm::MetaAdsCommentAction.record!(account: account, network: 'instagram', ad_id: ad_id, comment_id: 'r9', action: 'page_reply',
                                        actor: 'user', user: user)
      stub_comments(body: { data: [{ id: 'c9', text: 'Muito bom!', timestamp: 1.hour.ago.iso8601, from: { id: '501', username: 'carla.dias' },
                                     replies: { data: [{ id: 'r9', text: 'Obrigado!', timestamp: 5.minutes.ago.iso8601 }] } }] })

      reply = service.payload(ad_id)[:comments].sole[:replies].sole
      expect(reply[:author]).to eq(name: nil, username: 'lojaexemplo', is_page: true)
      expect(reply).to include(can_reply: false, can_hide: false, can_delete: true)
    end

    it 'resposta da conta com from, feita pelo app do Instagram e sem page_reply, é da conta' do
      stub_ad
      stub_comments(body: {
                      data: [{ id: 'c1', text: 'Muito bom!', timestamp: 1.hour.ago.iso8601, from: { id: '501', username: 'carla.dias' },
                               replies: { data: [{ id: 'r3', text: 'Valeu!', timestamp: 5.minutes.ago.iso8601,
                                                   from: { id: ig_id, username: 'lojaexemplo' } }] } }]
                    })

      reply = service.payload(ad_id)[:comments].sole[:replies].sole

      expect(Crm::MetaAdsCommentAction.count).to eq(0)
      expect(reply[:author]).to eq(name: nil, username: 'lojaexemplo', is_page: true)
      expect(reply).to include(can_reply: false, can_hide: false, can_delete: true)
    end

    it 'linha gravada para um comentário de primeiro nível não o faz da conta (a IA grava `reply` com o comentário do cliente)' do
      stub_ad
      stub_comments
      %w[reply page_reply].each do |action|
        Crm::MetaAdsCommentAction.record!(account: account, network: 'instagram', ad_id: ad_id, comment_id: 'c1', action: action,
                                          actor: 'ai')
      end

      first = service.payload(ad_id)[:comments].first

      expect(first[:author]).to include(username: 'carla.dias', is_page: false)
      expect(first).to include(can_reply: true, can_reply_private: true)
    end

    it 'resposta de outra pessoa em dobro: fica a de dentro, com o autor da cópia de cima' do
      stub_ad
      stub_comments(body: {
                      data: [
                        { id: 'r2', text: 'Também achei', timestamp: 5.minutes.ago.iso8601, from: { id: '502', username: 'isa.lima' } },
                        { id: 'c1', text: 'Muito bom!', timestamp: 1.hour.ago.iso8601, from: { id: '501', username: 'carla.dias' },
                          replies: { data: [{ id: 'r2', text: 'Também achei', timestamp: 5.minutes.ago.iso8601 }] } }
                      ]
                    })
      stub_request(:get, %r{#{ig}/#{media_id}\?}).to_return(status: 500, headers: json, body: {}.to_json)

      result = service.payload(ad_id)

      reply = result[:comments].sole[:replies].sole
      expect(reply[:author]).to eq(name: nil, username: 'isa.lima', is_page: false)
      expect(result[:total]).to eq(2)
    end

    it 'mostra a resposta no privado já enviada, com o caminho da conversa' do
      stub_ad
      stub_comments
      conversation = create(:conversation, account: account, inbox: channel.inbox)
      Crm::MetaAdsCommentAction.create!(account: account, network: 'instagram', comment_id: 'c1', action: 'private_reply',
                                        conversation: conversation, actor: 'user', user: user, at: 2.minutes.ago,
                                        attempted_at: 2.minutes.ago, confirmed_at: 2.minutes.ago)

      first = service.payload(ad_id)[:comments].first

      expect(first[:can_reply_private]).to be(false)
      expect(first[:private_reply]).to include(conversation_path: "/app/accounts/#{account.id}/conversations/#{conversation.display_id}")
    end

    it 'anúncio fora do Instagram: no_post, sem chamar o Instagram' do
      stub_ad(creative: { effective_object_story_id: '1_2' })

      expect(service.payload(ad_id)).to include(status: 'no_post', comments: [])
      expect(instagram_call).not_to have_been_made
    end

    it 'Instagram do anúncio sem caixa na conta: not_connected, com o @ quando a Meta diz' do
      stub_ad(creative: { effective_instagram_media_id: media_id, instagram_user_id: '17841499999999999' })
      stub_request(:get, meta_graph_url('17841499999999999')).with(query: hash_including({}))
                                                             .to_return(status: 200, headers: json, body: { username: 'outraloja' }.to_json)

      expect(service.payload(ad_id)).to include(status: 'not_connected', account: { username: 'outraloja', name: nil })
    end

    it 'caixa sem a permissão de comentários: needs_login' do
      stub_ad
      stub_comments(status: 400, body: { error: { code: 10, message: 'no permission' } })

      expect(service.payload(ad_id)).to include(status: 'needs_login', inbox_id: channel.inbox.id,
                                                account: { username: 'lojaexemplo', name: channel.inbox.name })
    end

    it 'caixa esperando nova autorização: needs_login, sem chamar o Instagram' do
      stub_ad
      allow(Channel::Instagram).to receive(:find_by).and_return(channel)
      allow(channel).to receive(:reauthorization_required?).and_return(true)

      expect(service.payload(ad_id)[:status]).to eq('needs_login')
      expect(instagram_call).not_to have_been_made
    end

    it 'anúncio de outra conta de anúncios: nil' do
      stub_ad(ad_account: '999')

      expect(service.payload(ad_id)).to be_nil
    end

    # #2358: ler os comentários (inclusive os ocultos) pede ver a caixa do Instagram, como em Seus posts.
    it 'quem não vê a caixa: not_inbox_member, só com o @ e sem chamar o Instagram' do
      stub_ad
      outsider = described_class.new(connection, inbox_access: ->(_inbox) { false }, can_manage: true)

      expect(outsider.payload(ad_id)).to eq(status: 'not_inbox_member', account: { username: 'lojaexemplo', name: nil },
                                            comments: [], total: 0, next_cursor: nil)
      expect(instagram_call).not_to have_been_made
    end

    it 'falha passageira do Instagram vira meta_unavailable' do
      stub_ad
      stub_comments(status: 500, body: { error: { code: 2 } })

      expect { service.payload(ad_id) }.to raise_error(described_class::Error) { |error| expect(error.code).to eq('meta_unavailable') }
    end
  end

  describe 'ações' do
    before { stub_ad }

    it 'responde em público e devolve a linha nova, marcada como sua' do
      stub_comment('c1')
      stub_request(:post, %r{#{ig}/c1/replies}).to_return(status: 200, headers: json, body: { id: 'c9' }.to_json)

      row = service.reply!(ad_id, 'c1', 'Temos sim', user: user)

      expect(row).to include(id: 'c9', text: 'Temos sim', can_reply: false)
      expect(row[:author]).to include(username: 'lojaexemplo', is_page: true)
      expect(Crm::MetaAdsCommentAction.sole).to have_attributes(account_id: account.id, network: 'instagram', ad_id: ad_id,
                                                                comment_id: 'c9', action: 'page_reply', actor: 'user', user_id: user.id)
    end

    it 'resposta aceita pela Meta não vira erro quando gravar a linha falha' do
      stub_comment('c1')
      stub_request(:post, %r{#{ig}/c1/replies}).to_return(status: 200, headers: json, body: { id: 'c9' }.to_json)
      allow(Crm::MetaAdsCommentAction).to receive(:record!).and_raise(NoMethodError, 'quebra fora do banco')
      tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
      allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)

      expect(service.reply!(ad_id, 'c1', 'Temos sim', user: user)).to include(id: 'c9')
      expect(ChatwootExceptionTracker).to have_received(:new).with(an_instance_of(NoMethodError), account: account)
      expect(tracker).to have_received(:capture_exception)
    end

    it 'resposta a uma resposta vai para o comentário de cima, como no app' do
      stub_comment('c1r', parent_id: 'c1')
      to_parent = stub_request(:post, %r{#{ig}/c1/replies}).to_return(status: 200, headers: json, body: { id: 'c9' }.to_json)

      service.reply!(ad_id, 'c1r', 'Temos sim', user: user)

      expect(to_parent).to have_been_requested.once
    end

    it 'recusa comentário de outra mídia como comment_not_found, sem agir' do
      stub_comment('c1', media: '1799999')

      expect { service.hide!(ad_id, 'c1', hidden: true) }.to raise_error(described_class::Error) { |e| expect(e.code).to eq('comment_not_found') }
      expect(a_request(:post, %r{#{ig}/c1})).not_to have_been_made
    end

    it 'oculta, mostra de novo e apaga' do
      stub_comment('c1')
      stub_request(:post, %r{#{ig}/c1\?}).to_return(status: 200, headers: json, body: { success: true }.to_json)
      stub_request(:delete, %r{#{ig}/c1\?}).to_return(status: 200, headers: json, body: { success: true }.to_json)

      expect(service.hide!(ad_id, 'c1', hidden: true)).to eq(id: 'c1', hidden: true)
      expect(service.hide!(ad_id, 'c1', hidden: false)).to eq(id: 'c1', hidden: false)
      expect(service.delete!(ad_id, 'c1')).to eq(id: 'c1')
    end

    # #2358: agir em comentário pede ver a caixa do Instagram, não só o privado.
    it 'quem não vê a caixa: not_inbox_member em responder, ocultar, apagar e no privado, sem chamar o Instagram' do
      outsider = described_class.new(connection, inbox_access: ->(_inbox) { false }, can_manage: true)
      refused = ->(code) { raise_error(described_class::Error) { |e| expect(e.code).to eq(code) } }

      expect { outsider.reply!(ad_id, 'c1', 'Temos sim', user: user) }.to refused.call('not_inbox_member')
      expect { outsider.hide!(ad_id, 'c1', hidden: true) }.to refused.call('not_inbox_member')
      expect { outsider.delete!(ad_id, 'c1') }.to refused.call('not_inbox_member')
      expect { outsider.private_reply!(ad_id, 'c1', 'Oi', user: user) }.to refused.call('not_inbox_member')
      expect(instagram_call).not_to have_been_made
      expect(Crm::MetaAdsCommentAction.count).to eq(0)
    end

    it 'quem não vê a caixa, com a caixa pedindo login: needs_login, sem ler comentário nem chamar o Instagram' do
      allow(Channel::Instagram).to receive(:find_by).and_return(channel)
      allow(channel).to receive(:reauthorization_required?).and_return(true)
      outsider = described_class.new(connection, inbox_access: ->(_inbox) { false }, can_manage: true)

      expect { outsider.hide!(ad_id, 'c1', hidden: true) }.to raise_error(described_class::Error) { |e| expect(e.code).to eq('needs_login') }
      expect(instagram_call).not_to have_been_made
    end

    it 'texto vazio ou longo demais: invalid_text, sem chamar a Meta' do
      expect { service.reply!(ad_id, 'c1', '  ', user: user) }.to raise_error(described_class::Error) { |e| expect(e.code).to eq('invalid_text') }
      expect { service.private_reply!(ad_id, 'c1', 'a' * 1001, user: user) }
        .to raise_error(described_class::Error) { |e| expect(e.code).to eq('invalid_text') }
      expect(instagram_call).not_to have_been_made
    end

    describe '#private_reply!' do
      before do
        stub_comment('c1')
        stub_request(:post, "#{ig}/#{ig_id}/messages").with(query: hash_including({}))
                                                      .to_return(status: 200, headers: json, body: { recipient_id: '7001',
                                                                                                     message_id: 'mid.1' }.to_json)
      end

      it 'manda, abre a conversa na caixa com a mensagem enviada e lembra que foi' do
        result = service.private_reply!(ad_id, 'c1', 'Oi, Carla!', user: user)

        message = Message.find_by(source_id: 'mid.1')
        expect(message).to have_attributes(content: 'Oi, Carla!', message_type: 'outgoing', sender: user, inbox_id: channel.inbox.id)
        expect(message.conversation.contact_inbox.source_id).to eq('7001')
        expect(message.conversation.contact.name).to eq('carla.dias')
        expect(result[:conversation_path]).to eq("/app/accounts/#{account.id}/conversations/#{message.conversation.display_id}")
        expect(Crm::MetaAdsCommentAction.find_by(comment_id: 'c1')).to have_attributes(actor: 'user', user_id: user.id,
                                                                                       conversation_id: message.conversation.id)
      end

      it 'usa a conversa aberta que a pessoa já tem na caixa' do
        contact_inbox = create(:contact_inbox, inbox: channel.inbox, source_id: '7001')
        open = create(:conversation, account: account, inbox: channel.inbox, contact: contact_inbox.contact, contact_inbox: contact_inbox)

        service.private_reply!(ad_id, 'c1', 'Oi!', user: user)

        expect(Message.find_by(source_id: 'mid.1').conversation).to eq(open)
      end

      it 'recusa explícita da Meta solta o comentário para tentar de novo' do
        stub_request(:post, "#{ig}/#{ig_id}/messages").with(query: hash_including({}))
                                                      .to_return(status: 400, headers: json, body: { error: { code: 100 } }.to_json)

        expect { service.private_reply!(ad_id, 'c1', 'Oi!', user: user) }
          .to raise_error(described_class::Error) { |e| expect(e.code).to eq('meta_refused') }
        expect(Crm::MetaAdsCommentAction.count).to eq(0)
      end

      it 'falha passageira mantém a reivindicação: a Meta pode ter entregado, e o privado não sai duas vezes' do
        stub_request(:post, "#{ig}/#{ig_id}/messages").with(query: hash_including({})).to_timeout

        expect { service.private_reply!(ad_id, 'c1', 'Oi!', user: user) }
          .to raise_error(described_class::Error) { |e| expect(e.code).to eq('meta_unavailable') }
        expect(Crm::MetaAdsCommentAction.find_by(comment_id: 'c1')).to have_attributes(confirmed_at: nil, failed_at: be_present)
        expect(Crm::MetaAdsCommentAction.find_by(comment_id: 'c1')).to be_releasable
      end

      it 'falha ao gravar a confirmação tenta de novo uma vez; se insistir, vai para o log e o privado segue' do
        failures = 1
        allow(Crm::MetaAdsCommentAction).to receive(:record!).and_wrap_original do |original, **attributes|
          original.call(**attributes).tap do |action|
            allow(action).to receive(:confirm!).and_wrap_original do |confirm|
              (failures -= 1).negative? ? confirm.call : raise(ActiveRecord::ConnectionTimeoutError)
            end
          end
        end
        service.private_reply!(ad_id, 'c1', 'Oi!', user: user)
        expect(Crm::MetaAdsCommentAction.find_by(comment_id: 'c1').confirmed_at).to be_present

        Crm::MetaAdsCommentAction.delete_all
        failures = 2
        allow(Rails.logger).to receive(:error)
        expect(service.private_reply!(ad_id, 'c1', 'Oi!', user: user)).to include(:sent_at)
        expect(Rails.logger).to have_received(:error).with(/confirm failed action_id=\d+ error=ActiveRecord::ConnectionTimeoutError/)
        expect(Crm::MetaAdsCommentAction.find_by(comment_id: 'c1')).to have_attributes(confirmed_at: nil, attempted_at: be_present)
      end

      it 'quem perdeu a reserva no meio (outra requisição a apagou e refez) não chama a Meta' do
        allow(Crm::MetaAdsCommentAction).to receive(:record!).and_wrap_original do |original, **attributes|
          original.call(**attributes).tap { |action| Crm::MetaAdsCommentAction.where(id: action.id).delete_all }
        end

        expect { service.private_reply!(ad_id, 'c1', 'Oi!', user: user) }
          .to raise_error(described_class::Error) { |e| expect(e.code).to eq('private_reply_retry') }
        expect(a_request(:post, %r{/messages})).not_to have_been_made
      end

      it 'com o envio em andamento, "Não foi enviado" não vale; parado há mais de IN_FLIGHT, vale' do
        stub_comments
        row = Crm::MetaAdsCommentAction.create!(account: account, network: 'instagram', comment_id: 'c1', action: 'private_reply',
                                                actor: 'user', ad_id: ad_id, at: 10.seconds.ago, attempted_at: 10.seconds.ago)

        expect(service.payload(ad_id)[:comments].first[:private_reply]).to include(confirmed: false, can_release: false)
        expect { service.release_private_reply!(ad_id, 'c1') }
          .to raise_error(described_class::Error) { |e| expect(e.code).to eq('private_reply_not_pending') }

        row.update!(attempted_at: (Crm::MetaAdsCommentAction::IN_FLIGHT + 1.second).ago)
        expect { service.release_private_reply!(ad_id, 'c1') }.to change(Crm::MetaAdsCommentAction, :count).by(-1)
      end

      def private_row(**attributes)
        Crm::MetaAdsCommentAction.create!(account: account, network: 'instagram', comment_id: 'c1', action: 'private_reply',
                                          actor: 'user', ad_id: ad_id, **attributes)
      end

      it 'sem confirmação (a chamada saiu), fica travado, nem dias depois, até alguém dizer "Não foi enviado"' do
        stub_comments
        private_row(at: 3.days.ago, attempted_at: 3.days.ago)

        expect(service.payload(ad_id)[:comments].first).to include(can_reply_private: false,
                                                                   private_reply: include(confirmed: false, can_release: true))
        expect { service.private_reply!(ad_id, 'c1', 'Oi!', user: user) }
          .to raise_error(described_class::Error) { |e| expect(e.code).to eq('private_reply_done') }
        expect(a_request(:post, %r{/messages})).not_to have_been_made

        service.release_private_reply!(ad_id, 'c1')
        expect(service.payload(ad_id)[:comments].first).to include(can_reply_private: true, private_reply: nil)
      end

      it 'reserva cujo envio nunca saiu (processo morreu antes da chamada) vence e o privado sai' do
        stub_comments
        private_row(at: (Crm::MetaAdsCommentAction::RESERVED_TTL + 1.minute).ago)

        expect(service.payload(ad_id)[:comments].first).to include(can_reply_private: true, private_reply: nil)
        service.private_reply!(ad_id, 'c1', 'Oi!', user: user)
        expect(Crm::MetaAdsCommentAction.where(comment_id: 'c1').sole).to have_attributes(attempted_at: be_present, confirmed_at: be_present)
      end

      it 'reserva recente (envio em andamento) ainda vale e não pode ser liberada' do
        private_row(at: 10.seconds.ago)

        expect { service.private_reply!(ad_id, 'c1', 'Oi!', user: user) }
          .to raise_error(described_class::Error) { |e| expect(e.code).to eq('private_reply_done') }
        expect { service.release_private_reply!(ad_id, 'c1') }
          .to raise_error(described_class::Error) { |e| expect(e.code).to eq('private_reply_not_pending') }
      end

      it '"Não foi enviado" não mexe em privado confirmado nem em outro anúncio' do
        private_row(at: 1.hour.ago, attempted_at: 1.hour.ago, confirmed_at: 1.hour.ago)

        expect { service.release_private_reply!(ad_id, 'c1') }
          .to raise_error(described_class::Error) { |e| expect(e.code).to eq('private_reply_not_pending') }
        expect { service.release_private_reply!('999', 'c1') }.to raise_error(described_class::Error)
        expect(Crm::MetaAdsCommentAction.count).to eq(1)
      end

      it 'aceito pela Meta, fica confirmado' do
        service.private_reply!(ad_id, 'c1', 'Oi!', user: user)

        expect(Crm::MetaAdsCommentAction.where(comment_id: 'c1').sole.confirmed_at).to be_present
      end

      it 'resposta a comentário não recebe o privado' do
        stub_comment('c9', parent_id: 'c1')

        expect { service.private_reply!(ad_id, 'c9', 'Oi!', user: user) }
          .to raise_error(described_class::Error) { |e| expect(e.code).to eq('private_reply_top_only') }
        expect(a_request(:post, %r{/messages})).not_to have_been_made
      end

      it 'depois de a Meta aceitar, erro ao abrir a conversa não vira falha' do
        allow(ConversationBuilder).to receive(:new).and_raise(ActiveRecord::RecordInvalid)
        tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
        allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)

        expect(service.private_reply!(ad_id, 'c1', 'Oi!', user: user)).to include(conversation_path: nil)
        expect(tracker).to have_received(:capture_exception)
      end

      it 'o eco que chegou antes não vira segunda mensagem' do
        echo_conversation = create(:conversation, account: account, inbox: channel.inbox)
        create(:message, conversation: echo_conversation, account: account, inbox: channel.inbox, source_id: 'mid.1',
                         message_type: :outgoing)

        expect { service.private_reply!(ad_id, 'c1', 'Oi!', user: user) }.not_to change(Message, :count)
        expect(Crm::MetaAdsCommentAction.find_by(comment_id: 'c1').conversation).to eq(echo_conversation)
      end

      it 'uma vez só por comentário' do
        Crm::MetaAdsCommentAction.create!(account: account, network: 'instagram', comment_id: 'c1', action: 'private_reply',
                                          actor: 'ai', at: Time.current)

        expect { service.private_reply!(ad_id, 'c1', 'Oi!', user: user) }
          .to raise_error(described_class::Error) { |e| expect(e.code).to eq('private_reply_done') }
        expect(a_request(:post, %r{/messages})).not_to have_been_made
      end

      it 'depois de 7 dias: private_reply_expired' do
        stub_comment('c1', timestamp: 8.days.ago)

        expect { service.private_reply!(ad_id, 'c1', 'Oi!', user: user) }
          .to raise_error(described_class::Error) { |e| expect(e.code).to eq('private_reply_expired') }
      end
    end
  end
end
