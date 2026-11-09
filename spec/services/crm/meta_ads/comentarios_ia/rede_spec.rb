require 'rails_helper'

RSpec.describe Crm::MetaAds::ComentariosIa::Rede do
  let(:account) { create(:account) }
  let(:care) { create(:crm_meta_ads_comment_care, account: account) }
  let(:registro) { Crm::MetaAds::ComentariosIa::Registro }
  let(:conversation) { instance_double(Conversation, id: 9) }
  # A linha de Crm::MetaAdsCommentAction (#2196) que a reivindicação devolve.
  let(:reivindicacao) { double }

  def comentario(**mudancas)
    Crm::MetaAds::ComentariosIa::Comentario.new(
      network: 'instagram', account_id: account.id, inbox_id: 1, owner_id: 'ig-1', post_id: '555_888', ad_id: nil,
      comment_id: '555_777', parent_id: nil, from_id: 'igsid-1', from_name: 'carla', text: 'Quanto custa?',
      created_time: Time.zone.parse('2026-10-27 10:00'), **mudancas
    )
  end

  before do
    allow(reivindicacao).to receive_messages(attempt!: true, confirm!: true, id: 7)
    allow(registro).to receive_messages(reivindicar!: reivindicacao, soltar!: 0, soltar_abandonada!: 0, gravar!: true)
  end

  describe 'Página (o Private Reply pelo Messenger)' do
    let(:channel) { instance_double(Channel::FacebookPage, page_id: '555', page_access_token: 'token-da-pagina') }
    let(:pagina) { described_class::Pagina.new(channel) }
    let(:graph) { 'https://graph.facebook.com/v22.0' }

    it 'responde ao comentário pelo Messenger, com o token da Página só no cabeçalho' do
      pedido = stub_request(:post, "#{graph}/555/messages")
               .with(headers: { 'Authorization' => 'Bearer token-da-pagina' },
                     body: hash_including('recipient' => { 'comment_id' => '555_777' }, 'message' => { 'text' => 'Oi!' },
                                          'messaging_type' => 'RESPONSE'))
               .to_return(status: 200, body: { recipient_id: 'psid-1', message_id: 'mid-1' }.to_json)

      envio = pagina.private_reply('555_777', { text: 'Oi!' })

      expect(pedido).to have_been_made
      expect(envio).to have_attributes(ok: true, recipient_id: 'psid-1', message_id: 'mid-1')
    end

    it 'recusa da Meta e falha de rede viram envio sem sucesso, com o erro limpo' do
      stub_request(:post, "#{graph}/555/messages").to_return(status: 400, body: { error: { code: 10, message: 'Fora' } }.to_json)
      expect(pagina.private_reply('555_777', { text: 'Oi!' })).to have_attributes(ok: false, erro: '10 - Fora')

      stub_request(:post, "#{graph}/555/messages").to_raise(Net::OpenTimeout)
      expect(pagina.private_reply('555_777', { text: 'Oi!' })).to have_attributes(ok: false, talvez_entregue: true)
    end

    it 'a recusa traz o código e o subcódigo da Meta (#2454), para decidir sem ler a mensagem' do
      stub_request(:post, "#{graph}/555/messages")
        .to_return(status: 400, body: { error: { code: 10, error_subcode: 2_018_278, message: 'Fora' } }.to_json)
      expect(pagina.private_reply('555_777', { text: 'Oi!' })).to have_attributes(ok: false, codigo: 10, subcodigo: 2_018_278)

      stub_request(:post, "#{graph}/555/messages").to_return(status: 503, body: 'indisponível')
      expect(pagina.private_reply('555_777', { text: 'Oi!' })).to have_attributes(codigo: nil, subcodigo: nil)

      stub_request(:post, "#{graph}/555/messages").to_return(status: 429, body: 'devagar')
      expect(pagina.private_reply('555_777', { text: 'Oi!' })).to have_attributes(ok: false, http: 429, talvez_entregue: false)
    end

    it 'só a recusa explícita (4xx) é certa; 5xx e rede podem ter entregado' do
      stub_request(:post, "#{graph}/555/messages").to_return(status: 400, body: { error: { code: 10, message: 'Fora' } }.to_json)
      expect(pagina.private_reply('555_777', { text: 'Oi!' }).talvez_entregue).to be_falsey

      stub_request(:post, "#{graph}/555/messages").to_return(status: 503, body: 'indisponível')
      expect(pagina.private_reply('555_777', { text: 'Oi!' })).to have_attributes(ok: false, talvez_entregue: true)
    end

    it 'erro de código (não de rede) sobe: não vira "pode ter saído"' do
      stub_request(:post, "#{graph}/555/messages").to_raise(NoMethodError)

      expect { pagina.private_reply('555_777', { text: 'Oi!' }) }.to raise_error(NoMethodError)
    end

    it 'id com cara de caminho não chega à Graph' do
      expect(pagina.private_reply('1/../me?x=1', { text: 'oi' })).to have_attributes(ok: false, erro: 'id_invalido')
      expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
    end
  end

  describe 'Facebook' do
    let(:canal) { instance_double(Channel::FacebookPage) }
    let(:inbox) { instance_double(Inbox, channel: canal, account: account) }
    let(:pagina) { instance_double(described_class::Pagina) }
    let(:servico) { double }
    let(:rede) { described_class::Facebook.new(inbox, comentario(network: 'facebook')) }

    before do
      allow(described_class::ComentariosDaPagina).to receive(:new).and_return(servico)
      allow(described_class::Pagina).to receive(:new).and_return(pagina)
      allow(Crm::MetaAds::ComentariosIa::Conversa).to receive(:no_messenger!).and_return(conversation)
    end

    it 'o privado pelo Messenger sai na Página com a pages_messaging concedida (#2307)' do
      permissao = instance_double(described_class::PermissaoDoMessenger, liberada?: false)
      allow(described_class::PermissaoDoMessenger).to receive(:new).with(canal).and_return(permissao)
      expect(rede.privado_disponivel?).to be(false)

      allow(permissao).to receive(:liberada?).and_return(true)
      expect(rede.privado_disponivel?).to be(true)
    end

    it 'a Meta recusou por permissão (#2307): o envio volta com o código, e a Página não perde o privado' do
      allow(described_class::PermissaoDoMessenger).to receive(:new)
      allow(pagina).to receive(:private_reply).and_return(described_class::Envio.new(ok: false, erro: '230 - Requires', codigo: 230))

      expect(rede.privado(care)).to have_attributes(ok: false, codigo: 230)
      expect(registro).to have_received(:soltar!).with(anything, 'private_reply')
      expect(described_class::PermissaoDoMessenger).not_to have_received(:new)
    end

    it 'reivindica, manda o privado com o botão do WhatsApp e abre a conversa no Messenger' do
      envio = described_class::Envio.new(ok: true, recipient_id: 'psid-1', message_id: 'mid-1')
      allow(pagina).to receive(:private_reply).and_return(envio)

      resultado = rede.privado(care)

      expect(registro).to have_received(:soltar_abandonada!).with(an_object_having_attributes(comment_id: '555_777')).ordered
      expect(registro).to have_received(:reivindicar!).with(an_object_having_attributes(comment_id: '555_777'), 'private_reply').ordered
      expect(reivindicacao).to have_received(:attempt!).ordered
      expect(pagina).to have_received(:private_reply).ordered
      expect(reivindicacao).to have_received(:confirm!).ordered
      expect(pagina).to have_received(:private_reply).with('555_777', hash_including(attachment: hash_including(type: 'template')))
      expect(resultado).to have_attributes(ok: true, conversation: conversation)
    end

    it 'a mensagem na caixa leva a marca de envio automático com o id da linha private_reply (#2212)' do
      envio = described_class::Envio.new(ok: true, recipient_id: 'psid-1', message_id: 'mid-1')
      allow(pagina).to receive(:private_reply).and_return(envio)

      rede.privado(care)

      expect(Crm::MetaAds::ComentariosIa::Conversa).to have_received(:no_messenger!).with(anything, envio, anything, 7)
    end

    it 'privado recusado: a reivindicação sai' do
      allow(pagina).to receive(:private_reply).and_return(described_class::Envio.new(ok: false, erro: '10 - Fora'))

      expect(rede.privado(care).ok).to be(false)
      expect(registro).to have_received(:soltar!).with(anything, 'private_reply')
      expect(reivindicacao).not_to have_received(:confirm!)
      expect(Crm::MetaAds::ComentariosIa::Conversa).not_to have_received(:no_messenger!)
    end

    describe 'na resposta a comentário (2º nível, #2454): o resultado fica consultável, sem texto de terceiro' do
      let(:rede) { described_class::Facebook.new(inbox, comentario(network: 'facebook', parent_id: '555_666')) }

      before { allow(registro).to receive(:recusa_do_privado!) }

      it 'aceito: a linha do privado guarda o id da mensagem' do
        allow(reivindicacao).to receive(:update!)
        allow(pagina).to receive(:private_reply).and_return(described_class::Envio.new(ok: true, recipient_id: 'psid-1', message_id: 'mid-1'))

        expect(rede.privado(care).ok).to be(true)
        expect(reivindicacao).to have_received(:update!).with(meta_message_id: 'mid-1')
      end

      it 'recusado (4xx): a reivindicação sai e a recusa fica com o código e o subcódigo; talvez saiu: nada' do
        recusa = described_class::Envio.new(ok: false, erro: '100 - Fora', codigo: 100, subcodigo: 33)
        allow(pagina).to receive(:private_reply).and_return(recusa)

        rede.privado(care)

        expect(registro).to have_received(:soltar!).with(anything, 'private_reply')
        expect(registro).to have_received(:recusa_do_privado!).with(an_object_having_attributes(comment_id: '555_777'), codigo: 100, subcodigo: 33)

        allow(pagina).to receive(:private_reply).and_return(described_class::Envio.new(ok: false, talvez_entregue: true))
        rede.privado(care)
        expect(registro).to have_received(:recusa_do_privado!).once
      end

      it 'recusa sem código da Meta: a reivindicação sai, mas nada é gravado como recusa (igual ao motor)' do
        allow(pagina).to receive(:private_reply).and_return(described_class::Envio.new(ok: false, erro: 'HTTP 400'))

        rede.privado(care)

        expect(registro).to have_received(:soltar!).with(anything, 'private_reply')
        expect(registro).not_to have_received(:recusa_do_privado!)
      end

      it 'o comentário de primeiro nível fica como antes: sem id da mensagem nem recusa gravada' do
        allow(reivindicacao).to receive(:update!)
        allow(pagina).to receive(:private_reply).and_return(described_class::Envio.new(ok: true, message_id: 'mid-1'),
                                                            described_class::Envio.new(ok: false, codigo: 100))
        primeiro = described_class::Facebook.new(inbox, comentario(network: 'facebook'))

        2.times { primeiro.privado(care) }

        expect(reivindicacao).not_to have_received(:update!)
        expect(registro).not_to have_received(:recusa_do_privado!)
      end
    end

    it 'privado que talvez saiu (rede, 5xx): a reivindicação fica, sem confirmar' do
      allow(pagina).to receive(:private_reply).and_return(described_class::Envio.new(ok: false, erro: 'HTTP 503', talvez_entregue: true))

      expect(rede.privado(care).ok).to be(false)
      expect(registro).not_to have_received(:soltar!)
      expect(reivindicacao).not_to have_received(:confirm!)
    end

    it 'privado que outra requisição já está mandando (attempt! falso): não chama a Meta de novo' do
      allow(reivindicacao).to receive(:attempt!).and_return(false)
      allow(pagina).to receive(:private_reply)

      expect(rede.privado(care).erro).to eq(described_class::JA_FEITO)
      expect(pagina).not_to have_received(:private_reply)
    end

    it 'privado já reivindicado: não chama a Meta' do
      allow(registro).to receive(:reivindicar!).and_return(false)
      allow(pagina).to receive(:private_reply)

      expect(rede.privado(care).erro).to eq(described_class::JA_FEITO)
      expect(pagina).not_to have_received(:private_reply)
      expect(reivindicacao).not_to have_received(:attempt!)
    end

    it 'responde e esconde pelo token da caixa, como IA (#2587)' do
      allow(servico).to receive_messages(reply_as_ai: { id: 'c-2' }, hide_as_ai: true)

      expect(rede.responder('Te chamei no Messenger')).to be(true)
      expect(rede.esconder).to be(true)
      expect(servico).to have_received(:reply_as_ai).with('555_888', '555_777', 'Te chamei no Messenger')
      expect(servico).to have_received(:hide_as_ai).with('555_888', '555_777', true)
    end

    it 'recusa do serviço vira false' do
      allow(servico).to receive(:reply_as_ai).and_raise(described_class::ComentariosDaPagina::Error.new('meta_refused'))

      expect(rede.responder('oi')).to be(false)
    end

    # #2587: a caixa da Página, não a conexão de Anúncios (a conta aqui nem tem uma).
    it 'age pela caixa da Página, sem pessoa abrindo a tela e sem conexão de Anúncios' do
      allow(servico).to receive(:hide_as_ai).and_return(true)

      rede.esconder

      expect(described_class::ComentariosDaPagina).to have_received(:new).with(canal, prazo: nil)
      expect(Crm::MetaAdsConnection.where(account_id: account.id)).not_to exist
    end

    describe 'ler (o evento leva só ids, #2327)' do
      it 'o texto e o nome como a Graph devolve' do
        allow(servico).to receive(:comment).with('555_888', '555_777')
                                           .and_return({ 'message' => 'Quanto custa?', 'from' => { 'id' => '9', 'name' => 'Ana' } })

        expect(rede.ler).to eq(text: 'Quanto custa?', from_name: 'Ana', from_id: '9')
      end

      it 'comentário de outro post ou de outra Página: nil, com o motivo no log só com ids' do
        allow(Rails.logger).to receive(:warn)
        allow(servico).to receive(:comment).and_raise(described_class::ComentariosDaPagina::Error.new('comment_not_found'))

        expect(rede.ler).to be_nil
        expect(Rails.logger).to have_received(:warn).with(include('comment_not_found', 'post=555_888', 'comment=555_777'))
      end

      it 'a Meta fora do ar: Indisponivel, para o job tentar de novo; outra recusa: nil' do
        allow(servico).to receive(:comment).and_raise(described_class::ComentariosDaPagina::Error.new('meta_unavailable'))
        expect { rede.ler }.to raise_error(described_class::Indisponivel)

        allow(servico).to receive(:comment).and_raise(described_class::ComentariosDaPagina::Error.new('meta_refused'))
        expect(rede.ler).to be_nil
      end

      it 'login caído ou permissão tirada: Indisponivel, como no Instagram (não descarta o comentário)' do
        allow(servico).to receive(:comment).and_raise(described_class::ComentariosDaPagina::Error.new('needs_login'))

        expect { rede.ler }.to raise_error(described_class::Indisponivel)
      end
    end

    describe 'ler_pai (#2454: o comentário que a resposta responde)' do
      let(:rede) { described_class::Facebook.new(inbox, comentario(network: 'facebook', parent_id: '555_666')) }

      it 'só o texto do comentário de cima, lido na Meta pelo id' do
        allow(servico).to receive(:comment).with('555_888', '555_666')
                                           .and_return({ 'message' => 'Tem em azul?', 'from' => { 'id' => '8', 'name' => 'Bia' } })

        expect(rede.ler_pai).to eq('Tem em azul?')
      end

      it 'comentário de primeiro nível, ou o de cima que não dá para ler: nil; a Meta fora do ar: Indisponivel' do
        expect(described_class::Facebook.new(inbox, comentario(network: 'facebook')).ler_pai).to be_nil

        allow(servico).to receive(:comment).and_raise(described_class::ComentariosDaPagina::Error.new('meta_refused'))
        expect(rede.ler_pai).to be_nil

        # Lido uma vez por comentário (#2458): cada cenário com a sua Rede.
        de_novo = described_class::Facebook.new(inbox, comentario(network: 'facebook', parent_id: '555_666'))
        allow(servico).to receive(:comment).and_raise(described_class::ComentariosDaPagina::Error.new('meta_unavailable'))
        expect { de_novo.ler_pai }.to raise_error(described_class::Indisponivel)
      end

      it 'lê o de cima uma vez só por comentário: o Classificador e a Escrita leem o mesmo (#2458)' do
        allow(servico).to receive(:comment).and_return({ 'message' => 'Tem em azul?' })

        2.times { expect(rede.ler_pai).to eq('Tem em azul?') }
        expect(servico).to have_received(:comment).once
      end
    end

    describe 'legenda (#2424)' do
      it 'o texto do post da Página' do
        allow(servico).to receive(:post_message).with('555_888').and_return('Seguro viagem com cobertura internacional')

        expect(rede.legenda).to eq('Seguro viagem com cobertura internacional')
      end

      it 'a Meta fora do ar: Indisponivel; outra recusa: nil' do
        allow(servico).to receive(:post_message).and_raise(described_class::ComentariosDaPagina::Error.new('meta_unavailable'))
        expect { rede.legenda }.to raise_error(described_class::Indisponivel)

        allow(servico).to receive(:post_message).and_raise(described_class::ComentariosDaPagina::Error.new('meta_refused'))
        expect(rede.legenda).to be_nil
      end
    end

    describe 'imagens (#2454)' do
      it 'as imagens do post da Página' do
        dados = { 'attachments' => { 'data' => [{ 'media' => { 'image' => { 'src' => 'https://fb.exemplo/1.jpg' } } }] } }
        allow(servico).to receive(:post_media).with('555_888').and_return(dados)

        expect(rede.imagens).to eq(['https://fb.exemplo/1.jpg'])
      end

      it 'a Meta fora do ar: Indisponivel; outra recusa: nenhuma' do
        allow(servico).to receive(:post_media).and_raise(described_class::ComentariosDaPagina::Error.new('meta_unavailable'))
        expect { rede.imagens }.to raise_error(described_class::Indisponivel)

        allow(servico).to receive(:post_media).and_raise(described_class::ComentariosDaPagina::Error.new('meta_refused'))
        expect(rede.imagens).to eq([])
      end

      it 'com prazo (a leitura da foto, dentro da requisição): o serviço lê com o prazo, contado de agora' do
        allow(servico).to receive(:post_media).and_return({})
        antes = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        rede.imagens(prazo: 3)

        expect(described_class::ComentariosDaPagina).to have_received(:new).with(canal, prazo: be_between(antes + 3, antes + 4))
      end
    end
  end

  describe 'Instagram' do
    let(:channel) { instance_double(Channel::Instagram) }
    let(:inbox) { instance_double(Inbox, channel: channel) }
    let(:privado) { double }
    let(:cliente) { double }
    let(:rede) { described_class::Instagram.new(inbox, comentario) }
    let(:ok) { Struct.new(:ok).new(true) }
    let(:recusa) { Struct.new(:ok).new(false) }

    before do
      stub_const('Instagram::CommentsClient', Class.new { def initialize(_channel, timeout: nil); end })
      allow(Crm::MetaAds::InstagramPrivateReply).to receive(:new).with(channel).and_return(privado)
      allow(Instagram::CommentsClient).to receive(:new).with(channel).and_return(cliente)
    end

    it 'o privado está liberado' do
      expect(rede.privado_disponivel?).to be(true)
    end

    it 'manda o privado pelo serviço do #2196, como IA, com o comentário no formato do webhook' do
      allow(privado).to receive(:perform!).and_return({ conversation: conversation, message: double })

      expect(rede.privado(care)).to have_attributes(ok: true, conversation: conversation)
      expect(privado).to have_received(:perform!).with(
        comment: { 'id' => '555_777', 'timestamp' => '2026-10-27T10:00:00Z', 'from' => { 'id' => 'igsid-1', 'username' => 'carla' } },
        text: care.texto_do_privado, actor: 'ai', ad_id: nil
      )
      expect(care.texto_do_privado).to eq(care.message.strip)
    end

    it 'na resposta a comentário (#2454), o serviço recebe o parent_id; a recusa traz o código e o subcódigo da Meta' do
      erro = Crm::MetaAds::InstagramPrivateReply::Error.new('meta_refused', meta_code: 100, meta_subcode: 2_534_023, meta_http: 400)
      allow(privado).to receive(:perform!).and_raise(erro)

      envio = described_class::Instagram.new(inbox, comentario(parent_id: '555_666')).privado(care)

      expect(envio).to have_attributes(ok: false, erro: 'meta_refused', codigo: 100, subcodigo: 2_534_023, http: 400)
      expect(privado).to have_received(:perform!).with(hash_including(comment: hash_including('parent_id' => '555_666')))
    end

    # #2519: o Esperando conta por anúncio só o primeiro nível, como a lista mostra.
    it 'o privado do comentário leva o anúncio; o da resposta a comentário, não' do
      allow(privado).to receive(:perform!).and_return({ conversation: conversation, message: double })

      described_class::Instagram.new(inbox, comentario(ad_id: '120')).privado(care)
      described_class::Instagram.new(inbox, comentario(ad_id: '120', parent_id: '555_666')).privado(care)

      expect(privado).to have_received(:perform!).with(hash_including(ad_id: '120')).once
      expect(privado).to have_received(:perform!).with(hash_including(ad_id: nil)).once
    end

    it 'recusa do serviço (4xx) vira envio sem sucesso com o código, sem "pode ter saído"' do
      allow(privado).to receive(:perform!).and_raise(Crm::MetaAds::InstagramPrivateReply::Error.new('meta_refused'))

      expect(rede.privado(care)).to have_attributes(ok: false, erro: 'meta_refused', talvez_entregue: false)
    end

    it 'a Meta não respondeu (o serviço marcou failed_at): pode ter saído' do
      Crm::MetaAdsCommentAction.record!(account: account, network: 'instagram', comment_id: '555_777', action: 'private_reply',
                                        actor: 'ai', attempted_at: Time.current, failed_at: Time.current)
      allow(privado).to receive(:perform!).and_raise(Crm::MetaAds::InstagramPrivateReply::Error.new('meta_unavailable'))

      expect(rede.privado(care)).to have_attributes(ok: false, erro: 'meta_unavailable', talvez_entregue: true)
    end

    it 'privado já feito ou saindo em outra requisição: já feito, nada a mostrar' do
      %w[private_reply_done private_reply_retry].each do |codigo|
        allow(privado).to receive(:perform!).and_raise(Crm::MetaAds::InstagramPrivateReply::Error.new(codigo))

        expect(rede.privado(care).erro).to eq(described_class::JA_FEITO)
      end
    end

    describe 'legenda (#2424)' do
      let(:result) { Meta::AdsGraphClient::Result }

      it 'a legenda do post, lida pelo id da mídia' do
        allow(cliente).to receive(:caption).with('555_888').and_return(result.new(ok: true, data: { 'caption' => 'Seguro viagem' }))

        expect(rede.legenda).to eq('Seguro viagem')
      end

      # Lida uma vez por comentário (#2458): cada cenário com a sua Rede.
      it 'post sem legenda ou que não dá para ler: nil; Meta fora do ar ou token caído: Indisponivel' do
        nova = -> { described_class::Instagram.new(inbox, comentario) }
        allow(cliente).to receive(:caption).and_return(result.new(ok: true, data: { 'id' => '555_888' }))
        expect(nova.call.legenda).to be_nil

        allow(cliente).to receive(:caption).and_return(result.new(ok: false, http_code: 400, error_code: 100))
        expect(nova.call.legenda).to be_nil

        allow(cliente).to receive(:caption).and_return(result.new(ok: false, http_code: 500, error_code: 2))
        expect { nova.call.legenda }.to raise_error(described_class::Indisponivel)

        allow(cliente).to receive(:caption).and_return(result.new(ok: false, http_code: 400, error_code: 190))
        expect { nova.call.legenda }.to raise_error(described_class::Indisponivel)
      end

      it 'lê a legenda uma vez só por comentário (#2458)' do
        allow(cliente).to receive(:caption).and_return(result.new(ok: true, data: { 'caption' => 'Seguro viagem' }))

        2.times { expect(rede.legenda).to eq('Seguro viagem') }
        expect(cliente).to have_received(:caption).once
      end
    end

    describe 'imagens (#2454)' do
      let(:result) { Meta::AdsGraphClient::Result }

      it 'as imagens do post, lidas pelo id da mídia (carrossel incluído)' do
        dados = { 'media_type' => 'CAROUSEL_ALBUM', 'children' => { 'data' => [
          { 'media_type' => 'IMAGE', 'media_url' => 'https://cdn.exemplo/1.jpg' },
          { 'media_type' => 'VIDEO', 'thumbnail_url' => 'https://cdn.exemplo/2.jpg' }
        ] } }
        allow(cliente).to receive(:media).with('555_888').and_return(result.new(ok: true, data: dados))

        expect(rede.imagens).to eq(%w[https://cdn.exemplo/1.jpg https://cdn.exemplo/2.jpg])
      end

      it 'que não dá para ler: nenhuma; Meta fora do ar ou token caído: Indisponivel' do
        allow(cliente).to receive(:media).and_return(result.new(ok: false, http_code: 400, error_code: 100))
        expect(rede.imagens).to eq([])

        allow(cliente).to receive(:media).and_return(result.new(ok: false, http_code: 500, error_code: 2))
        expect { rede.imagens }.to raise_error(described_class::Indisponivel)

        allow(cliente).to receive(:media).and_return(result.new(ok: false, http_code: 400, error_code: 190))
        expect { rede.imagens }.to raise_error(described_class::Indisponivel)
      end

      it 'com prazo (a leitura da foto, dentro da requisição): um cliente com esse prazo; sem resposta nele, Indisponivel' do
        lento = double
        allow(Instagram::CommentsClient).to receive(:new).with(channel, timeout: 3).and_return(lento)
        allow(lento).to receive(:media).and_return(result.new(ok: false, http_code: nil, error_message: 'Net::ReadTimeout'))

        expect { rede.imagens(prazo: 3) }.to raise_error(described_class::Indisponivel)
      end
    end

    describe 'ler (o evento leva só ids, #2327)' do
      let(:result) { Meta::AdsGraphClient::Result }

      it 'o texto e o username como a Graph devolve' do
        allow(cliente).to receive(:comment).with('555_777')
                                           .and_return(result.new(ok: true, data: { 'text' => 'Quanto custa?',
                                                                                    'from' => { 'id' => 7, 'username' => 'carla' } }))

        expect(rede.ler).to eq(text: 'Quanto custa?', from_name: 'carla', from_id: '7')
      end

      it 'comentário de outro post (o evento não bate com a Graph): nil, como o of_post? do Facebook' do
        allow(cliente).to receive(:comment).and_return(result.new(ok: true, data: { 'text' => 'oi', 'media' => { 'id' => '999' },
                                                                                    'from' => { 'id' => 7 } }))
        expect(rede.ler).to be_nil

        allow(cliente).to receive(:comment).and_return(result.new(ok: true, data: { 'text' => 'oi', 'media' => { 'id' => '555_888' },
                                                                                    'from' => { 'id' => 7 } }))
        expect(rede.ler).to include(text: 'oi')
      end

      it 'comentário apagado: nil' do
        allow(cliente).to receive(:comment).and_return(result.new(ok: false, http_code: 400, error_code: 100))

        expect(rede.ler).to be_nil
      end

      it 'token caído ou permissão tirada: Indisponivel, sem descartar o comentário' do
        allow(cliente).to receive(:comment).and_return(result.new(ok: false, http_code: 400, error_code: 190))
        expect { rede.ler }.to raise_error(described_class::Indisponivel)

        allow(cliente).to receive(:comment).and_return(result.new(ok: false, http_code: 403, error_code: 10))
        expect { rede.ler }.to raise_error(described_class::Indisponivel)
      end

      it 'a Meta fora do ar (rede, 5xx, limite): Indisponivel, para o job tentar de novo' do
        allow(cliente).to receive(:comment).and_return(result.new(ok: false, http_code: nil))
        expect { rede.ler }.to raise_error(described_class::Indisponivel)

        allow(cliente).to receive(:comment).and_return(result.new(ok: false, http_code: 500, error_code: 2))
        expect { rede.ler }.to raise_error(described_class::Indisponivel)
      end
    end

    describe 'ler_pai (#2454: o comentário que a resposta responde)' do
      let(:result) { Meta::AdsGraphClient::Result }
      let(:rede) { described_class::Instagram.new(inbox, comentario(parent_id: '555_666')) }

      it 'só o texto do comentário de cima, lido na Meta pelo id' do
        allow(cliente).to receive(:comment).with('555_666')
                                           .and_return(result.new(ok: true, data: { 'text' => 'Tem em azul?', 'from' => { 'id' => 8 } }))

        expect(rede.ler_pai).to eq('Tem em azul?')
      end

      it 'comentário de primeiro nível, ou o de cima apagado: nil; a Meta fora do ar: Indisponivel' do
        allow(cliente).to receive(:comment)
        expect(described_class::Instagram.new(inbox, comentario).ler_pai).to be_nil
        expect(cliente).not_to have_received(:comment)

        allow(cliente).to receive(:comment).and_return(result.new(ok: false, http_code: 400, error_code: 100))
        expect(rede.ler_pai).to be_nil

        # Lido uma vez por comentário (#2458): o cenário seguinte com a sua Rede.
        de_novo = described_class::Instagram.new(inbox, comentario(parent_id: '555_666'))
        allow(cliente).to receive(:comment).and_return(result.new(ok: false, http_code: 500, error_code: 2))
        expect { de_novo.ler_pai }.to raise_error(described_class::Indisponivel)
      end
    end

    it 'responde e esconde; só grava o que a Meta aceitou' do
      allow(cliente).to receive_messages(reply: ok, hide: recusa)

      expect(rede.responder('Te chamei no privado')).to be(true)
      expect(rede.esconder).to be(false)
      expect(cliente).to have_received(:hide).with('555_777', hidden: true)
      expect(registro).to have_received(:gravar!).with(anything, 'reply')
      expect(registro).not_to have_received(:gravar!).with(anything, 'hide')
    end
  end

  describe '.privado_liberado? (#2307)' do
    let(:pagina) { create(:inbox, account: account, channel: build(:channel_facebook_page, account: account)).channel }

    it 'no Instagram sempre; no Facebook, o que a Meta concedeu à Página; sem caixa ou outra rede, nunca' do
      permissao = instance_double(described_class::PermissaoDoMessenger, liberada?: true)
      allow(described_class::PermissaoDoMessenger).to receive(:new).with(pagina).and_return(permissao)

      expect(described_class.privado_liberado?('instagram', nil)).to be(true)
      expect(described_class.privado_liberado?('facebook', pagina.inbox)).to be(true)
      expect(described_class.privado_liberado?('facebook', nil)).to be(false)
      expect(described_class.privado_liberado?('whatsapp', pagina.inbox)).to be(false)

      allow(permissao).to receive(:liberada?).and_return(false)
      expect(described_class.privado_liberado?('facebook', pagina.inbox)).to be(false)
    end

    it 'a flag antiga (#2613) não libera mais nada sozinha' do
      allow(described_class::PermissaoDoMessenger).to receive(:new)
        .and_return(instance_double(described_class::PermissaoDoMessenger, liberada?: false))
      account.enable_features!('meta_ads_comentarios_privado_facebook')

      expect(described_class.privado_liberado?('facebook', pagina.inbox)).to be(false)
    end
  end

  describe '.sem_permissao? (#2307)' do
    it 'só a recusa por permissão: 200–299 e o 10 sem subcódigo' do
      expect(described_class.sem_permissao?(230, nil)).to be(true)
      expect(described_class.sem_permissao?(200, 1_545_041)).to be(true)
      expect(described_class.sem_permissao?(10, nil)).to be(true)
      expect(described_class.sem_permissao?(10, 2_018_278)).to be(false)
      expect(described_class.sem_permissao?(100, 33)).to be(false)
      expect(described_class.sem_permissao?(nil, nil)).to be(false)
    end
  end
end
