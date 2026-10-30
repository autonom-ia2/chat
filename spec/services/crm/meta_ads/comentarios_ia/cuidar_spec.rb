require 'rails_helper'

RSpec.describe Crm::MetaAds::ComentariosIa::Cuidar do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let!(:care) { create(:crm_meta_ads_comment_care, account: account, target_id: '1790') }
  let(:rede) { instance_double(Crm::MetaAds::ComentariosIa::Rede::Facebook, responder: true, esconder: true, privado_disponivel?: true) }
  let(:classificador) { instance_double(Crm::MetaAds::ComentariosIa::Classificador) }
  let(:conversa) { class_double(Crm::MetaAds::ComentariosIa::Conversa) }
  let(:registro) { class_double(Crm::MetaAds::ComentariosIa::Registro) }
  let(:conversation) { instance_double(Conversation, id: 77, created_at: 1.minute.from_now) }
  let(:enviado) { Crm::MetaAds::ComentariosIa::Rede::Envio.new(ok: true, conversation: conversation) }
  let(:agora) { 1.minute.ago }

  def comentario(**mudancas)
    Crm::MetaAds::ComentariosIa::Comentario.new(
      network: 'instagram', account_id: account.id, inbox_id: inbox.id, owner_id: 'ig-1', post_id: '1790', ad_id: nil,
      comment_id: 'c-1', parent_id: nil, from_id: 'igsid-1', created_time: agora, **mudancas
    )
  end

  # O comentário depois da leitura na Meta: o evento leva só ids (#2327).
  def lido(**mudancas)
    comentario(**mudancas).lido(text: 'Quanto custa?', from_name: 'carla.mendes')
  end

  def cuidar(item = comentario)
    described_class.new(item, rede: rede, classificador: classificador, conversa: conversa, registro: registro).call
  end

  def decide(decisao)
    allow(classificador).to receive(:decidir!).and_return(decisao)
  end

  before do
    account.enable_features!(described_class::FLAG)
    allow(registro).to receive_messages(reservar!: true, hoje: 1, vez: 0, gravar!: true, vincular!: 1, soltar!: 1,
                                        reservar_pessoa!: true, soltar_pessoa!: 1)
    allow(conversa).to receive_messages(anotar!: conversation, para_voce!: conversation)
    allow(rede).to receive_messages(privado: enviado, ler: { text: 'Quanto custa?', from_name: 'carla.mendes' })
  end

  it 'lê o comentário na Meta antes de perguntar ao Jev' do
    decide('no_reply')

    cuidar

    expect(rede).to have_received(:ler).ordered
    expect(classificador).to have_received(:decidir!).with('Quanto custa?').ordered
  end

  it 'comentário vindo da lista (sem o id de quem comentou): usa o lido na Meta' do
    decide('private')
    allow(rede).to receive(:ler).and_return({ text: 'Quanto custa?', from_name: 'carla.mendes', from_id: 'igsid-9' })

    cuidar(comentario(from_id: nil))

    expect(conversa).to have_received(:anotar!).with(conversation, an_object_having_attributes(from_id: 'igsid-9'), care, nova: true)
  end

  it 'a Meta diz que não dá para ler (apagado, sem permissão): descartado, sem Jev e sem soltar a leitura' do
    allow(classificador).to receive(:decidir!)
    allow(rede).to receive(:ler).and_return(nil)

    cuidar

    expect(classificador).not_to have_received(:decidir!)
    expect(registro).to have_received(:reservar!).with(comentario)
    expect(registro).not_to have_received(:soltar!)
  end

  it 'a Meta não responde à leitura: solta a leitura e sobe, para o job tentar de novo' do
    allow(rede).to receive(:ler).and_raise(Crm::MetaAds::ComentariosIa::Rede::Indisponivel)

    expect { cuidar }.to raise_error(Crm::MetaAds::ComentariosIa::Rede::Indisponivel)
    expect(registro).to have_received(:soltar!).with(comentario, 'ai_seen')
  end

  it 'manda o privado, põe o comentário no topo da conversa e responde no comentário com a frase da vez' do
    decide('private')
    allow(registro).to receive(:vez).and_return(1)

    cuidar

    expect(rede).to have_received(:privado).with(care)
    expect(conversa).to have_received(:anotar!).with(conversation, lido, care, nova: true)
    expect(registro).to have_received(:vincular!).with(lido, 'private_reply', conversation)
    expect(rede).to have_received(:responder).with('Te mandei os detalhes no privado!')
  end

  it 'mesma pessoa comentando de novo no post (a reserva dela já existe): um privado só, sem resposta pública' do
    decide('private')
    allow(registro).to receive(:reservar_pessoa!).with(lido).and_return(false)

    cuidar

    expect(rede).not_to have_received(:privado)
    expect(rede).not_to have_received(:responder)
    expect(registro).to have_received(:gravar!).with(lido, 'private_reply_already')
  end

  it 'sem saber quem comentou: não manda privado, fica com o dono' do
    decide('private')
    allow(rede).to receive(:ler).and_return({ text: 'Quanto custa?', from_name: 'carla' })

    cuidar(comentario(from_id: nil))

    expect(rede).not_to have_received(:privado)
    expect(registro).to have_received(:gravar!).with(anything, 'ai_unread')
  end

  it 'conversa que a pessoa já tinha aberta na caixa não conta como nova' do
    decide('private')
    allow(conversation).to receive(:created_at).and_return(1.day.ago)

    cuidar

    expect(conversa).to have_received(:anotar!).with(conversation, lido, care, nova: false)
  end

  it 'erro antes de agir na Meta solta a leitura, para o job tentar de novo' do
    allow(classificador).to receive(:decidir!).and_raise(ActiveRecord::ConnectionTimeoutError)

    expect { cuidar }.to raise_error(ActiveRecord::ConnectionTimeoutError)
    expect(registro).to have_received(:soltar!).with(lido, 'ai_seen')
  end

  it 'Jev fora do ar: solta a leitura e sobe o erro, para o job tentar de novo' do
    allow(classificador).to receive(:decidir!).and_raise(TypesafeAi::Decisor::Error.new('typesafe_timeout'))

    expect { cuidar }.to raise_error(TypesafeAi::Decisor::Error)
    expect(registro).to have_received(:soltar!).with(lido, 'ai_seen')
    expect(rede).not_to have_received(:privado)
  end

  it 'falha ao soltar a leitura não troca o erro que faz o job tentar de novo' do
    allow(rede).to receive(:ler).and_raise(Crm::MetaAds::ComentariosIa::Rede::Indisponivel)
    allow(registro).to receive(:soltar!).and_raise(ActiveRecord::ConnectionTimeoutError)
    allow(ChatwootExceptionTracker).to receive(:new).and_return(instance_double(ChatwootExceptionTracker, capture_exception: true))

    expect { cuidar }.to raise_error(Crm::MetaAds::ComentariosIa::Rede::Indisponivel)
  end

  it 'erro antes de reservar não solta a leitura de outro job' do
    allow(registro).to receive(:reservar!).and_raise(ActiveRecord::ConnectionTimeoutError)

    expect { cuidar }.to raise_error(ActiveRecord::ConnectionTimeoutError)
    expect(registro).not_to have_received(:soltar!)
  end

  it 'falha ao anotar a conversa depois do privado: vai ao rastreador, a resposta pública sai e nada é solto' do
    decide('private')
    allow(conversa).to receive(:anotar!).and_raise(ActiveRecord::StatementInvalid)
    rastreador = instance_double(ChatwootExceptionTracker, capture_exception: true)
    allow(ChatwootExceptionTracker).to receive(:new).and_return(rastreador)

    cuidar

    expect(rastreador).to have_received(:capture_exception)
    expect(rede).to have_received(:responder)
    expect(registro).not_to have_received(:soltar!)
    expect(registro).not_to have_received(:soltar_pessoa!)
  end

  it 'a Meta aceitou, mas a conversa não foi gravada: avisa no log com ids e responde em público' do
    decide('private')
    allow(rede).to receive(:privado).and_return(Crm::MetaAds::ComentariosIa::Rede::Envio.new(ok: true, conversation: nil))
    allow(Rails.logger).to receive(:warn)

    cuidar

    expect(Rails.logger).to have_received(:warn).with(include('privado sem conversa gravada', 'comment=c-1'))
    expect(rede).to have_received(:responder)
  end

  it 'a Meta recusou a resposta pública: avisa no log com ids' do
    decide('private')
    allow(rede).to receive(:responder).and_return(false)
    allow(Rails.logger).to receive(:warn)

    cuidar

    expect(Rails.logger).to have_received(:warn).with(include('recusou reply', 'comment=c-1'))
  end

  it 'privado sem resposta da Meta (pode ter saído): a reserva da pessoa fica, e a conversa vai para conferir' do
    decide('private')
    allow(rede).to receive(:privado)
      .and_return(Crm::MetaAds::ComentariosIa::Rede::Envio.new(ok: false, erro: 'meta_unavailable', talvez_entregue: true))

    cuidar

    expect(registro).not_to have_received(:soltar_pessoa!)
    expect(conversa).to have_received(:para_voce!).with(lido, care, 'private_reply_unsure')
    expect(registro).to have_received(:gravar!).with(lido, 'private_reply_unsure', conversation: conversation)
  end

  it 'responde o preço em público quando a pessoa perguntou o preço e a chave está ligada' do
    decide('price')

    cuidar

    expect(rede).to have_received(:responder).with(care.price_reply)
  end

  it 'privado recusado pela Meta: nada em público, a conversa fica para a pessoa' do
    decide('private')
    allow(rede).to receive(:privado).and_return(Crm::MetaAds::ComentariosIa::Rede::Envio.new(ok: false, erro: 'meta_refused'))

    cuidar

    expect(rede).not_to have_received(:responder)
    expect(registro).to have_received(:soltar_pessoa!).with(lido)
    expect(conversa).to have_received(:para_voce!).with(lido, care, 'private_reply_failed')
    expect(registro).to have_received(:gravar!).with(lido, 'private_reply_failed', conversation: conversation)
  end

  it 'privado que já tinha saído (pela pessoa ou outro job): não faz mais nada' do
    decide('private')
    allow(rede).to receive(:privado)
      .and_return(Crm::MetaAds::ComentariosIa::Rede::Envio.new(ok: false, erro: Crm::MetaAds::ComentariosIa::Rede::JA_FEITO))

    cuidar

    expect(rede).not_to have_received(:responder)
    expect(conversa).not_to have_received(:para_voce!)
    expect(registro).not_to have_received(:soltar_pessoa!)
    expect(registro).to have_received(:gravar!).with(lido, 'private_reply_already')
  end

  it 'reclamação: não responde, abre a conversa urgente para a pessoa' do
    decide('to_you')

    cuidar

    expect(rede).not_to have_received(:privado)
    expect(rede).not_to have_received(:responder)
    expect(conversa).to have_received(:para_voce!).with(lido, care, 'to_you')
    expect(registro).to have_received(:gravar!).with(lido, 'to_you', conversation: conversation)
  end

  it 'propaganda: esconde o comentário' do
    decide('hide')

    cuidar

    expect(rede).to have_received(:esconder)
  end

  it 'a Meta recusou o esconder: avisa no log com ids' do
    decide('hide')
    allow(rede).to receive(:esconder).and_return(false)
    allow(Rails.logger).to receive(:warn)

    cuidar

    expect(Rails.logger).to have_received(:warn).with(include('recusou hide', 'comment=c-1'))
    expect(registro).to have_received(:gravar!).with(lido, 'ai_unread')
  end

  it 'marcação de amigo ou elogio: não faz nada além de ler' do
    decide('no_reply')

    cuidar

    expect(rede).not_to have_received(:privado)
    expect(rede).not_to have_received(:esconder)
    expect(registro).to have_received(:reservar!).with(comentario)
  end

  it 'post sem oferta nunca manda privado, mesmo se o Jev pedir: a pergunta fica com o dono' do
    care.update!(offer: nil)
    decide('price')

    cuidar

    expect(rede).not_to have_received(:privado)
    expect(registro).to have_received(:gravar!).with(lido, 'kept_for_owner')
  end

  it 'post sem oferta, com o "para quem" do dono: manda o privado a quem é o caso' do
    care.update!(offer: nil, para_quem: 'Quem pedir o link do e-book')
    decide('private')

    cuidar

    expect(rede).to have_received(:privado).with(care)
  end

  it 'rede em que o privado ainda não está liberado (Facebook, até a pages_messaging): a pergunta fica com o dono' do
    allow(rede).to receive(:privado_disponivel?).and_return(false)
    decide('price')

    cuidar

    expect(rede).not_to have_received(:privado)
    expect(rede).not_to have_received(:responder)
    expect(registro).to have_received(:gravar!).with(lido, 'kept_for_owner')
    expect(conversa).not_to have_received(:para_voce!)
  end

  it 'não era o caso (no_reply): só a leitura, sem ficar com o dono' do
    decide('no_reply')

    cuidar

    expect(registro).not_to have_received(:gravar!)
  end

  it 'sem certeza do Jev: não age, e o comentário fica com o dono como "não cuidei"' do
    decide(nil)

    cuidar

    expect(rede).not_to have_received(:privado)
    expect(conversa).not_to have_received(:para_voce!)
    expect(registro).to have_received(:gravar!).with(lido, 'ai_unread')
  end

  it 'Jev barrado (teto do dia ou flag): não sobe, fica com o dono como "não cuidei"' do
    allow(classificador).to receive(:decidir!).and_raise(Crm::MetaAds::ComentariosIa::Classificador::Bloqueado.new('daily_limit'))

    cuidar

    expect(registro).to have_received(:gravar!).with(lido, 'ai_unread')
    expect(registro).not_to have_received(:soltar!)
  end

  it 'teto do dia, contado depois da reserva (ela conta): o comentário fica com o dono, sem ir ao Jev' do
    allow(registro).to receive(:hoje).and_return(described_class::TETO_DIARIO + 1)
    allow(classificador).to receive(:decidir!)

    cuidar

    expect(classificador).not_to have_received(:decidir!)
    expect(rede).not_to have_received(:ler)
    expect(registro).to have_received(:gravar!).with(comentario, 'ai_unread')
  end

  it 'no teto exato (o 200º do dia), ainda cuida' do
    allow(registro).to receive(:hoje).and_return(described_class::TETO_DIARIO)
    decide('no_reply')

    cuidar

    expect(classificador).to have_received(:decidir!)
  end

  describe 'o que não chega ao Jev' do
    before { allow(classificador).to receive(:decidir!) }

    it 'comentário já reivindicado (a Meta reenvia o webhook, ou outro job pegou antes)' do
      allow(registro).to receive(:reservar!).and_return(false)
      cuidar
      expect(classificador).not_to have_received(:decidir!)
    end

    it 'flag desligada' do
      account.disable_features!(described_class::FLAG)
      cuidar
      expect(classificador).not_to have_received(:decidir!)
      expect(registro).not_to have_received(:reservar!)
    end

    it 'post sem cuidado, ou com o cuidado pausado' do
      care.update!(status: 'paused')
      cuidar
      expect(registro).not_to have_received(:reservar!)
    end

    it 'resposta a outro comentário' do
      cuidar(comentario(parent_id: 'c-0'))
      expect(registro).not_to have_received(:reservar!)
    end

    it 'comentário com mais de 7 dias, que não aceita mais privado' do
      cuidar(comentario(created_time: 8.days.ago))
      expect(registro).not_to have_received(:reservar!)
    end

    it 'caixa de outra conta' do
      cuidar(comentario(inbox_id: create(:inbox).id))
      expect(registro).not_to have_received(:reservar!)
    end

    it 'caixa que não é do Instagram nem do Messenger' do
      described_class.new(comentario, classificador: classificador, conversa: conversa, registro: registro).call
      expect(registro).not_to have_received(:reservar!)
    end
  end

  it 'usa o cuidado do anúncio quando o comentário veio dele' do
    anuncio = create(:crm_meta_ads_comment_care, account: account, target_kind: 'ad', target_id: '120', network: 'both',
                                                 message: 'Mensagem do anúncio')
    decide('private')

    cuidar(comentario(ad_id: '120'))

    expect(rede).to have_received(:privado).with(anuncio)
  end
end
