require 'rails_helper'

RSpec.describe Crm::MetaAds::ComentariosIa::Cuidar do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let!(:care) { create(:crm_meta_ads_comment_care, account: account, target_id: '1790') }
  # Com a flag do cuidado, a Escrita (#2458) lê a legenda e o comentário de cima; sem chave da conta, as frases fixas.
  let(:rede) do
    instance_double(Crm::MetaAds::ComentariosIa::Rede::Facebook, responder: true, esconder: true, privado_disponivel?: true,
                                                                 legenda: nil, ler_pai: nil)
  end
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

  # Sem certeza (decisao nil), a IA escolheu algo com certeza baixa: a decisão não vale, mas fica gravada.
  def decide(decisao, escolha: decisao || 'private', certeza: decisao ? 0.9 : 0.4)
    avaliacao = Crm::MetaAds::ComentariosIa::Classificador::Avaliacao.new(chave: decisao, escolha: escolha, certeza: certeza)
    allow(classificador).to receive(:avaliar!).and_return(avaliacao)
    avaliacao
  end

  before do
    account.enable_features!(described_class::FLAG)
    allow(registro).to receive_messages(reservar!: true, vez: 0, gravar!: true, vincular!: 1, soltar!: 1,
                                        reservar_pessoa!: true, soltar_pessoa!: 1, decisao!: 1, sem_cuidado!: true)
    allow(conversa).to receive_messages(anotar!: conversation, para_voce!: conversation)
    allow(rede).to receive_messages(privado: enviado, ler: { text: 'Quanto custa?', from_name: 'carla.mendes' })
  end

  it 'lê o comentário na Meta antes de perguntar à IA' do
    decide('no_reply')

    cuidar

    expect(rede).to have_received(:ler).ordered
    expect(classificador).to have_received(:avaliar!).with('Quanto custa?').ordered
  end

  it 'comentário vindo da lista (sem o id de quem comentou): usa o lido na Meta' do
    decide('private')
    allow(rede).to receive(:ler).and_return({ text: 'Quanto custa?', from_name: 'carla.mendes', from_id: 'igsid-9' })

    cuidar(comentario(from_id: nil))

    expect(conversa).to have_received(:anotar!).with(conversation, an_object_having_attributes(from_id: 'igsid-9'), care, nova: true)
  end

  it 'a Meta diz que não dá para ler (apagado, sem permissão): descartado, sem IA e sem soltar a leitura' do
    allow(classificador).to receive(:avaliar!)
    allow(rede).to receive(:ler).and_return(nil)

    cuidar

    expect(classificador).not_to have_received(:avaliar!)
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

    expect(rede).to have_received(:privado).with(care, texto: nil)
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
    allow(classificador).to receive(:avaliar!).and_raise(ActiveRecord::ConnectionTimeoutError)

    expect { cuidar }.to raise_error(ActiveRecord::ConnectionTimeoutError)
    expect(registro).to have_received(:soltar!).with(lido, 'ai_seen')
  end

  it 'erro ao reservar a pessoa (antes da Meta): solta a leitura e não chama a Meta, para o job tentar de novo' do
    decide('private')
    allow(registro).to receive(:reservar_pessoa!).and_raise(ActiveRecord::RecordInvalid)

    expect { cuidar }.to raise_error(ActiveRecord::RecordInvalid)
    expect(registro).to have_received(:soltar!).with(lido, 'ai_seen')
    expect(rede).not_to have_received(:privado)
  end

  it 'erro depois de chamar a Meta não solta a leitura: o privado pode ter saído' do
    decide('private')
    allow(rede).to receive(:privado).and_raise(ActiveRecord::ConnectionTimeoutError)

    expect { cuidar }.to raise_error(ActiveRecord::ConnectionTimeoutError)
    expect(registro).not_to have_received(:soltar!)
  end

  it 'comentário do anúncio sem o post: não manda privado (a pessoa é por post), fica com o dono' do
    create(:crm_meta_ads_comment_care, account: account, target_kind: 'ad', target_id: '120', network: 'both')
    decide('private')

    cuidar(comentario(post_id: nil, ad_id: '120'))

    expect(rede).not_to have_received(:privado)
    expect(registro).to have_received(:gravar!).with(anything, 'ai_unread')
  end

  it 'IA fora do ar: solta a leitura e sobe o erro, para o job tentar de novo' do
    allow(classificador).to receive(:avaliar!).and_raise(Crm::MetaAds::ComentariosIa::Classificador::Indisponivel.new('ai_timeout'))

    expect { cuidar }.to raise_error(Crm::MetaAds::ComentariosIa::Classificador::Indisponivel)
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
    expect(registro).to have_received(:gravar!).with(lido, 'ai_unread')
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

  it 'privado que já tinha saído (pela pessoa ou outro job), confirmado pela Meta: "já recebeu", sem mais nada' do
    decide('private')
    Crm::MetaAdsCommentAction.record!(account: account, network: 'instagram', comment_id: 'c-1', action: 'private_reply', actor: 'user')
                             .update!(confirmed_at: Time.current)
    allow(rede).to receive(:privado)
      .and_return(Crm::MetaAds::ComentariosIa::Rede::Envio.new(ok: false, erro: Crm::MetaAds::ComentariosIa::Rede::JA_FEITO))

    cuidar

    expect(rede).not_to have_received(:responder)
    expect(conversa).not_to have_received(:para_voce!)
    expect(registro).not_to have_received(:soltar_pessoa!)
    expect(registro).to have_received(:gravar!).with(lido, 'private_reply_already')
  end

  it 'outro envio ainda saindo (sem confirmação): não diz "já recebeu"; solta a pessoa e fica como "não cuidei"' do
    decide('private')
    Crm::MetaAdsCommentAction.record!(account: account, network: 'instagram', comment_id: 'c-1', action: 'private_reply', actor: 'user')
    allow(rede).to receive(:privado)
      .and_return(Crm::MetaAds::ComentariosIa::Rede::Envio.new(ok: false, erro: Crm::MetaAds::ComentariosIa::Rede::JA_FEITO))

    cuidar

    expect(registro).to have_received(:soltar_pessoa!).with(lido)
    expect(registro).to have_received(:gravar!).with(lido, 'ai_unread')
    expect(registro).not_to have_received(:gravar!).with(lido, 'private_reply_already')
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

  it 'post sem oferta nunca manda privado, mesmo se a IA pedir: a pergunta fica com o dono' do
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

    expect(rede).to have_received(:privado).with(care, texto: nil)
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

  it 'sem certeza da IA: não age, e o comentário fica com o dono como "não cuidei"' do
    avaliacao = decide(nil)

    cuidar

    expect(rede).not_to have_received(:privado)
    expect(conversa).not_to have_received(:para_voce!)
    expect(registro).to have_received(:gravar!).with(lido, 'ai_unread')
    expect(registro).to have_received(:decisao!).with(lido, avaliacao)
  end

  it 'pergunta com a legenda do post, lida na Meta depois do comentário (#2424)' do
    avaliacao = Crm::MetaAds::ComentariosIa::Classificador::Avaliacao.new(chave: 'no_reply', escolha: 'no_reply', certeza: 0.9)
    allow(rede).to receive(:legenda).and_return('Seguro viagem com cobertura internacional')
    allow(Crm::MetaAds::ComentariosIa::Classificador).to receive(:new).and_return(classificador)
    allow(classificador).to receive(:avaliar!).and_return(avaliacao)

    described_class.new(comentario, rede: rede, conversa: conversa, registro: registro).call

    expect(Crm::MetaAds::ComentariosIa::Classificador).to have_received(:new)
      .with(care: care, legenda: 'Seguro viagem com cobertura internacional', foto: nil)
  end

  it 'pergunta também com o que a foto do post mostra, lido do banco, sem chamar a Meta nem a IA da foto (#2454)' do
    create(:crm_meta_ads_post_reading, account: account, network: 'instagram', post_id: '1790', description: 'Vestido azul',
                                       correction: 'Vestido midi azul-marinho')
    allow(rede).to receive(:legenda).and_return(nil)
    allow(Crm::MetaAds::ComentariosIa::Classificador).to receive(:new).and_return(classificador)
    decide('no_reply')

    described_class.new(comentario, rede: rede, conversa: conversa, registro: registro).call

    expect(Crm::MetaAds::ComentariosIa::Classificador).to have_received(:new).with(care: care, legenda: nil, foto: 'Vestido midi azul-marinho')
  end

  it 'grava o que a IA escolheu, a certeza e o motivo também quando ela age, antes de mandar o privado (#2424)' do
    avaliacao = decide('private')

    cuidar

    expect(registro).to have_received(:decisao!).with(lido, avaliacao).ordered
    expect(rede).to have_received(:privado).with(care, texto: nil).ordered
  end

  it 'IA barrada (flag desligada ou sem chave): não sobe, fica com o dono como "não cuidei"' do
    allow(classificador).to receive(:avaliar!).and_raise(Crm::MetaAds::ComentariosIa::Classificador::Bloqueado.new('feature_disabled'))

    cuidar

    expect(registro).to have_received(:gravar!).with(lido, 'ai_unread')
    expect(registro).not_to have_received(:soltar!)
  end

  it 'sem teto de uso (#2454): com centenas de comentários lidos hoje na conta, ainda cuida do próximo' do
    250.times do |indice|
      Crm::MetaAdsCommentAction.record!(account: account, network: 'instagram', comment_id: "lido-#{indice}", action: 'ai_seen', actor: 'ai')
    end
    decide('no_reply')

    described_class.new(comentario, rede: rede, classificador: classificador, conversa: conversa).call

    expect(classificador).to have_received(:avaliar!).with('Quanto custa?')
    expect(Crm::MetaAdsCommentAction.where(account_id: account.id, comment_id: 'c-1', action: 'ai_unread')).not_to exist
  end

  # #2519: as linhas do Registro são o que o Esperando conta por anúncio, e o número conta o mesmo que a lista mostra.
  describe 'o anúncio nas linhas do Registro (Esperando)' do
    before do
      create(:crm_meta_ads_comment_care, account: account, target_kind: 'ad', target_id: '120', network: 'both', post_ids: %w[1790])
    end

    def cuidar_de_verdade(item)
      decide(nil)
      described_class.new(item, rede: rede, classificador: classificador, conversa: conversa).call
    end

    it 'no Facebook (o evento vem sem ad_id), com o cuidado de um anúncio: a linha leva o anúncio, e o Esperando a conta' do
      cuidar_de_verdade(comentario(network: 'facebook', ad_id: nil))

      expect(Crm::MetaAdsCommentAction.where(comment_id: 'c-1').pluck(:action, :ad_id)).to contain_exactly(%w[ai_seen 120], %w[ai_unread 120])
      expect(Crm::MetaAds::ComentariosIa::Esperando.por_anuncio(account.id, %w[120])).to eq('120' => 1)
    end

    it 'a resposta dentro de um comentário vai sem anúncio: a lista mostra só o primeiro nível, e o número também' do
      account.enable_features!(described_class::FLAG)
      allow(rede).to receive(:ler_pai).and_return({ text: 'Tem desconto?', from_name: 'ana' })
      cuidar_de_verdade(comentario(ad_id: '120', parent_id: 'c-0'))

      expect(Crm::MetaAdsCommentAction.where(comment_id: 'c-1').pluck(:ad_id).uniq).to eq([nil])
      expect(Crm::MetaAds::ComentariosIa::Esperando.por_anuncio(account.id, %w[120])).to eq('120' => 0)
    end
  end

  describe 'o que não chega à IA' do
    before { allow(classificador).to receive(:avaliar!) }

    it 'comentário já reivindicado (a Meta reenvia o webhook, ou outro job pegou antes)' do
      allow(registro).to receive(:reservar!).and_return(false)
      cuidar
      expect(classificador).not_to have_received(:avaliar!)
    end

    it 'flag desligada' do
      account.disable_features!(described_class::FLAG)
      cuidar
      expect(classificador).not_to have_received(:avaliar!)
      expect(registro).not_to have_received(:reservar!)
      expect(registro).not_to have_received(:sem_cuidado!)
    end

    # #2519: nada some em silêncio. O comentário de cliente sem cuidado ligado fica registrado (no_care), para o
    # Esperando contar o que está com o dono.
    it 'anúncio sem cuidado, ou com o cuidado pausado: não chega à IA, mas fica registrado (no_care)' do
      care.update!(status: 'paused')
      cuidar(comentario(ad_id: '120'))
      expect(registro).not_to have_received(:reservar!)
      expect(registro).to have_received(:sem_cuidado!).with(comentario(ad_id: '120'))
    end

    it 'resposta dentro de um comentário de anúncio, sem cuidado: não registra (a lista mostra só o primeiro nível)' do
      care.update!(status: 'paused')
      cuidar(comentario(ad_id: '120', parent_id: 'c-0'))
      expect(registro).not_to have_received(:sem_cuidado!)
    end

    it 'post sem cuidado: não chega à IA e não registra (sem o anúncio, nenhuma leitura usaria a linha)' do
      care.update!(status: 'paused')
      cuidar
      expect(registro).not_to have_received(:reservar!)
      expect(registro).not_to have_received(:sem_cuidado!)
    end

    # #2519: passados 10 min o comentário aparece ao dono; o job pode ainda tentar de novo. A IA não age por cima dele.
    it 'a pessoa já respondeu, escondeu ou apagou o comentário: a IA não age' do
      pessoa = create(:user, account: account)
      %w[reply hide delete].each_with_index do |acao, indice|
        Crm::MetaAdsCommentAction.record!(account: account, network: 'instagram', comment_id: "c-#{indice}", action: acao, actor: 'user',
                                          user: pessoa)
        cuidar(comentario(comment_id: "c-#{indice}"))
      end

      expect(registro).not_to have_received(:reservar!)
    end

    it 'sem cuidado, não registra o que não é do motor: flag desligada, mais de 7 dias, o da própria conta' do
      care.destroy!
      cuidar(comentario(ad_id: '120', created_time: 8.days.ago))
      cuidar(comentario(ad_id: '120', from_id: 'ig-1'))
      account.disable_features!(described_class::FLAG)
      cuidar(comentario(ad_id: '120'))

      expect(registro).not_to have_received(:sem_cuidado!)
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

    expect(rede).to have_received(:privado).with(anuncio, texto: nil)
  end
end
