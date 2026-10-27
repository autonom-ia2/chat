require 'rails_helper'

RSpec.describe Crm::MetaAds::ComentariosIa::Cuidar do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let!(:care) { create(:crm_meta_ads_comment_care, account: account, target_id: '1790') }
  let(:rede) { instance_double(Crm::MetaAds::ComentariosIa::Rede) }
  let(:classificador) { instance_double(Crm::MetaAds::ComentariosIa::Classificador) }
  let(:conversa) { class_double(Crm::MetaAds::ComentariosIa::Conversa) }
  let(:registro) { class_double(Crm::MetaAds::ComentariosIa::Registro) }
  let(:conversation) { instance_double(Conversation, id: 77) }
  let(:enviado) { Crm::MetaAds::ComentariosIa::Rede::Envio.new(ok: true, recipient_id: 'igsid-1', message_id: 'mid-1') }
  let(:recusado) { Crm::MetaAds::ComentariosIa::Rede::Envio.new(ok: false, erro: '10 - fora da janela') }
  let(:agora) { 1.minute.ago }

  def comentario(**mudancas)
    Crm::MetaAds::ComentariosIa::Comentario.new(
      network: 'instagram', account_id: account.id, inbox_id: inbox.id, owner_id: 'ig-1', post_id: '1790', ad_id: nil,
      comment_id: 'c-1', parent_id: nil, from_id: 'igsid-1', from_name: 'carla.mendes', text: 'Quanto custa?',
      created_time: agora, **mudancas
    )
  end

  def cuidar(item = comentario)
    described_class.new(item, rede: rede, classificador: classificador, conversa: conversa, registro: registro).call
  end

  before do
    account.enable_features!(described_class::FLAG)
    allow(registro).to receive_messages(ja_cuidado?: false, hoje: 0, gravar!: true, vez: 0)
    allow(conversa).to receive_messages(do_privado!: conversation, para_voce!: conversation)
    allow(rede).to receive_messages(private_reply: enviado, reply: enviado, hide: enviado)
  end

  it 'manda o privado, abre a conversa e responde no comentário com a frase da vez' do
    allow(classificador).to receive(:decidir).and_return('private')
    allow(registro).to receive(:vez).and_return(1)

    cuidar

    expect(rede).to have_received(:private_reply).with('c-1', care.message, button: care.button)
    expect(conversa).to have_received(:do_privado!).with(comentario, care, enviado)
    expect(rede).to have_received(:reply).with('c-1', 'Te mandei os detalhes no privado!')
    expect(registro).to have_received(:gravar!).with(comentario, 'private_reply', conversation: conversation)
    expect(registro).to have_received(:gravar!).with(comentario, 'reply')
  end

  it 'responde o preço em público quando a pessoa perguntou o preço e a chave está ligada' do
    allow(classificador).to receive(:decidir).and_return('price')

    cuidar

    expect(rede).to have_received(:reply).with('c-1', care.price_reply)
  end

  it 'privado recusado pela Meta: nada em público, a conversa fica para a pessoa' do
    allow(classificador).to receive(:decidir).and_return('private')
    allow(rede).to receive(:private_reply).and_return(recusado)

    cuidar

    expect(rede).not_to have_received(:reply)
    expect(conversa).to have_received(:para_voce!).with(comentario, care, 'failed')
    expect(registro).to have_received(:gravar!).with(comentario, 'failed', conversation: conversation)
  end

  it 'reclamação: não responde, abre a conversa urgente para a pessoa' do
    allow(classificador).to receive(:decidir).and_return('to_you')

    cuidar

    expect(rede).not_to have_received(:private_reply)
    expect(rede).not_to have_received(:reply)
    expect(conversa).to have_received(:para_voce!).with(comentario, care, 'to_you')
    expect(registro).to have_received(:gravar!).with(comentario, 'to_you', conversation: conversation)
  end

  it 'propaganda: esconde o comentário' do
    allow(classificador).to receive(:decidir).and_return('hide')

    cuidar

    expect(rede).to have_received(:hide).with('c-1')
    expect(registro).to have_received(:gravar!).with(comentario, 'hide')
  end

  it 'marcação de amigo ou elogio: só registra' do
    allow(classificador).to receive(:decidir).and_return('no_reply')

    cuidar

    expect(rede).not_to have_received(:private_reply)
    expect(registro).to have_received(:gravar!).with(comentario, 'no_reply')
  end

  it 'post sem oferta nunca manda privado, mesmo se o Jev pedir' do
    care.update!(offer: nil)
    allow(classificador).to receive(:decidir).and_return('price')

    cuidar

    expect(rede).not_to have_received(:private_reply)
    expect(registro).to have_received(:gravar!).with(comentario, 'no_reply')
  end

  it 'sem certeza do Jev, não faz nada' do
    allow(classificador).to receive(:decidir).and_return(nil)

    cuidar

    expect(registro).not_to have_received(:gravar!)
  end

  describe 'o que não chega ao Jev' do
    before { allow(classificador).to receive(:decidir) }

    it 'flag desligada' do
      account.disable_features!(described_class::FLAG)
      cuidar
      expect(classificador).not_to have_received(:decidir)
    end

    it 'post sem cuidado, ou com o cuidado pausado' do
      care.update!(status: 'paused')
      cuidar
      expect(classificador).not_to have_received(:decidir)
    end

    it 'resposta a outro comentário' do
      cuidar(comentario(parent_id: 'c-0'))
      expect(classificador).not_to have_received(:decidir)
    end

    it 'comentário já cuidado (a Meta reenvia o webhook)' do
      allow(registro).to receive(:ja_cuidado?).and_return(true)
      cuidar
      expect(classificador).not_to have_received(:decidir)
    end

    it 'teto do dia atingido: os próximos ficam para a pessoa' do
      allow(registro).to receive(:hoje).and_return(described_class::TETO_DIARIO)
      cuidar
      expect(classificador).not_to have_received(:decidir)
    end

    it 'comentário com mais de 7 dias, que não aceita mais privado' do
      cuidar(comentario(created_time: 8.days.ago))
      expect(classificador).not_to have_received(:decidir)
    end

    it 'caixa de outra conta' do
      cuidar(comentario(inbox_id: create(:inbox).id))
      expect(classificador).not_to have_received(:decidir)
    end
  end

  it 'usa o cuidado do anúncio quando o comentário veio dele' do
    anuncio = create(:crm_meta_ads_comment_care, account: account, target_kind: 'ad', target_id: '120', network: 'both',
                                                 message: 'Mensagem do anúncio')
    allow(classificador).to receive(:decidir).and_return('private')

    cuidar(comentario(ad_id: '120'))

    expect(rede).to have_received(:private_reply).with('c-1', anuncio.message, button: anuncio.button)
  end
end
