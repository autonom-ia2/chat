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
    allow(reivindicacao).to receive(:confirm!)
    allow(registro).to receive_messages(reivindicar!: reivindicacao, soltar!: 0, soltar_vencida!: 0, gravar!: true)
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

    it 'só a recusa explícita (4xx) é certa; 5xx e rede podem ter entregado' do
      stub_request(:post, "#{graph}/555/messages").to_return(status: 400, body: { error: { code: 10, message: 'Fora' } }.to_json)
      expect(pagina.private_reply('555_777', { text: 'Oi!' }).talvez_entregue).to be_falsey

      stub_request(:post, "#{graph}/555/messages").to_return(status: 503, body: 'indisponível')
      expect(pagina.private_reply('555_777', { text: 'Oi!' })).to have_attributes(ok: false, talvez_entregue: true)
    end

    it 'id com cara de caminho não chega à Graph' do
      expect(pagina.private_reply('1/../me?x=1', { text: 'oi' })).to have_attributes(ok: false, erro: 'id_invalido')
      expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
    end
  end

  describe 'Facebook' do
    let(:inbox) { instance_double(Inbox, channel: instance_double(Channel::FacebookPage)) }
    let(:pagina) { instance_double(described_class::Pagina) }
    let(:servico) { double }
    let(:rede) { described_class::Facebook.new(inbox, comentario(network: 'facebook')) }

    before do
      stub_const('Crm::MetaAds::FacebookComments', Class.new { def initialize(_conexao); end })
      stub_const('Crm::MetaAds::FacebookComments::Error', Class.new(StandardError))
      allow(Crm::MetaAds::FacebookComments).to receive(:new).and_return(servico)
      allow(Crm::MetaAdsConnection).to receive(:find_by).with(account_id: account.id).and_return(instance_double(Crm::MetaAdsConnection))
      allow(described_class::Pagina).to receive(:new).and_return(pagina)
      allow(Crm::MetaAds::ComentariosIa::Conversa).to receive(:no_messenger!).and_return(conversation)
    end

    it 'reivindica, manda o privado com o botão do WhatsApp e abre a conversa no Messenger' do
      envio = described_class::Envio.new(ok: true, recipient_id: 'psid-1', message_id: 'mid-1')
      allow(pagina).to receive(:private_reply).and_return(envio)

      resultado = rede.privado(care)

      expect(registro).to have_received(:soltar_vencida!).with(an_object_having_attributes(comment_id: '555_777')).ordered
      expect(registro).to have_received(:reivindicar!).with(an_object_having_attributes(comment_id: '555_777'), 'private_reply').ordered
      expect(reivindicacao).to have_received(:confirm!)
      expect(pagina).to have_received(:private_reply).with('555_777', hash_including(attachment: hash_including(type: 'template')))
      expect(resultado).to have_attributes(ok: true, conversation: conversation)
    end

    it 'privado recusado: a reivindicação sai' do
      allow(pagina).to receive(:private_reply).and_return(described_class::Envio.new(ok: false, erro: '10 - Fora'))

      expect(rede.privado(care).ok).to be(false)
      expect(registro).to have_received(:soltar!).with(anything, 'private_reply')
      expect(reivindicacao).not_to have_received(:confirm!)
      expect(Crm::MetaAds::ComentariosIa::Conversa).not_to have_received(:no_messenger!)
    end

    it 'privado que talvez saiu (rede, 5xx): a reivindicação fica, sem confirmar, até vencer' do
      allow(pagina).to receive(:private_reply).and_return(described_class::Envio.new(ok: false, erro: 'HTTP 503', talvez_entregue: true))

      expect(rede.privado(care).ok).to be(false)
      expect(registro).not_to have_received(:soltar!)
      expect(reivindicacao).not_to have_received(:confirm!)
    end

    it 'privado já reivindicado: não chama a Meta' do
      allow(registro).to receive(:reivindicar!).and_return(false)
      allow(pagina).to receive(:private_reply)

      expect(rede.privado(care).erro).to eq(described_class::JA_FEITO)
      expect(pagina).not_to have_received(:private_reply)
    end

    it 'responde e esconde pelo serviço do #2197, como IA' do
      allow(servico).to receive_messages(reply_on_post!: { id: 'c-2' }, hide_on_post!: true)

      expect(rede.responder('Te chamei no Messenger')).to be(true)
      expect(rede.esconder).to be(true)
      expect(servico).to have_received(:reply_on_post!).with('555_888', '555_777', 'Te chamei no Messenger', actor: 'ai')
      expect(servico).to have_received(:hide_on_post!).with('555_888', '555_777', true, actor: 'ai')
    end

    it 'recusa do serviço vira false' do
      allow(servico).to receive(:reply_on_post!).and_raise(Crm::MetaAds::FacebookComments::Error)

      expect(rede.responder('oi')).to be(false)
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
      stub_const('Crm::MetaAds::InstagramPrivateReply', Class.new { def initialize(_channel); end })
      stub_const('Crm::MetaAds::InstagramPrivateReply::Error', Class.new(StandardError) { def code = 'meta_refused' })
      stub_const('Instagram::CommentsClient', Class.new { def initialize(_channel); end })
      allow(Crm::MetaAds::InstagramPrivateReply).to receive(:new).with(channel).and_return(privado)
      allow(Instagram::CommentsClient).to receive(:new).with(channel).and_return(cliente)
    end

    it 'manda o privado pelo serviço do #2196, como IA, com o comentário no formato do webhook' do
      allow(privado).to receive(:perform!).and_return({ conversation: conversation, message: double })

      expect(rede.privado(care)).to have_attributes(ok: true, conversation: conversation)
      expect(privado).to have_received(:perform!).with(
        comment: { 'id' => '555_777', 'timestamp' => '2026-10-27T10:00:00Z', 'from' => { 'id' => 'igsid-1', 'username' => 'carla' } },
        text: care.message, actor: 'ai', ad_id: nil
      )
    end

    it 'erro do serviço vira envio sem sucesso com o código' do
      allow(privado).to receive(:perform!).and_raise(Crm::MetaAds::InstagramPrivateReply::Error)

      expect(rede.privado(care)).to have_attributes(ok: false, erro: 'meta_refused')
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
end
