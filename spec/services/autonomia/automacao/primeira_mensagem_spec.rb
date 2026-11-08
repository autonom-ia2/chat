require 'rails_helper'

# #2527: quem começou a conversa e se a mensagem do gatilho é a primeira. A Boas-vindas lê os dois em mensagem.criada.
RSpec.describe Autonomia::Automacao::PrimeiraMensagem do
  let(:account) { create(:account) }
  let(:conversa) { create(:conversation, account: account) }

  def mensagem(message_type, **atributos)
    create(:message, conversation: conversa, account: account, inbox: conversa.inbox, message_type: message_type, **atributos)
  end

  def iniciada_por = described_class.iniciada_por(conversa.reload)

  it 'fica vazia sem mensagem, e nenhuma é a primeira', :aggregate_failures do
    expect(iniciada_por).to be_nil
    expect(described_class.primeira?(build(:message, conversation: conversa, account: account))).to be(false)
  end

  it 'é do cliente quando a primeira chegou dele; só ela é a primeira', :aggregate_failures do
    chegou = mensagem(:incoming)
    resposta = mensagem(:outgoing)

    expect(iniciada_por).to eq('cliente')
    expect([described_class.primeira?(chegou), described_class.primeira?(resposta)]).to eq([true, false])
  end

  # A conversa que nasce de comentário do Instagram (#2212) começa pelo privado da empresa: o texto do comentário é de
  # terceiro e não vira mensagem (ConversaCanal::ComentarioDoInstagram). É a primeira forma da lista.
  it 'é da equipe quando a primeira saiu daqui: resposta ou privado do comentário, modelo, campanha ou ligação feita',
     :aggregate_failures do
    formas = [
      [:outgoing, {}],
      [:template, {}],
      [:outgoing, { additional_attributes: { 'campaign_id' => 1 } }],
      [:outgoing, { content_type: :voice_call }]
    ]

    formas.each do |message_type, atributos|
      nova = create(:conversation, account: account)
      create(:message, conversation: nova, account: account, inbox: nova.inbox, message_type: message_type, **atributos)
      expect(described_class.iniciada_por(nova)).to eq('equipe'), "#{message_type} #{atributos}"
    end
  end

  it 'é do cliente na ligação recebida' do
    mensagem(:incoming, content_type: :voice_call)

    expect(iniciada_por).to eq('cliente')
  end

  it 'pula a atividade da plataforma e a nota interna', :aggregate_failures do
    atividade = mensagem(:activity, content: 'Conversa criada')
    nota = mensagem(:outgoing, private: true)
    chegou = mensagem(:incoming)

    expect(iniciada_por).to eq('cliente')
    expect([atividade, nota, chegou].map { |cada| described_class.primeira?(cada) }).to eq([false, false, true])
  end

  it 'na conversa resolvida que o cliente reabre, continua de quem começou, e a mensagem nova não é a primeira',
     :aggregate_failures do
    mensagem(:outgoing)
    conversa.update!(status: :resolved)
    reabriu = mensagem(:incoming)

    expect(iniciada_por).to eq('equipe')
    expect(described_class.primeira?(reabriu)).to be(false)
  end

  # Coexistência do WhatsApp: o histórico entra depois (id maior), mas com a data original (created_at menor).
  it 'com histórico importado, a mensagem antiga diz quem começou e a nova não é a primeira', :aggregate_failures do
    nova = mensagem(:incoming)
    importada = mensagem(:outgoing, created_at: 2.days.ago)

    expect(iniciada_por).to eq('equipe')
    expect([described_class.primeira?(importada), described_class.primeira?(nova)]).to eq([true, false])
  end

  it 'com duas mensagens no mesmo instante, só a de id menor é a primeira', :aggregate_failures do
    instante = 1.hour.ago
    antes = mensagem(:incoming, created_at: instante)
    depois = mensagem(:outgoing, created_at: instante)

    expect(antes.id).to be < depois.id
    expect(iniciada_por).to eq('cliente')
    expect([described_class.primeira?(antes), described_class.primeira?(depois)]).to eq([true, false])
  end

  # #2526: cada caminho que cria conversa a partir de comentário (Crm::MetaAds::ComentariosIa::Conversa e o privado da
  # tela, InstagramPrivateReply). A conversa que a plataforma abriu é da equipe; a que o cliente já tinha, continua dele.
  describe 'conversa que nasce de comentário' do
    let(:care) { create(:crm_meta_ads_comment_care, account: account, target_id: '1790') }
    let(:instagram) { create(:channel_instagram, account: account).inbox }
    let(:pagina) do
      stub_request(:post, %r{graph\.facebook\.com/.*/subscribed_apps})
      create(:inbox, account: account, channel: create(:channel_facebook_page, account: account))
    end
    let(:conversas) { Crm::MetaAds::ComentariosIa::Conversa }
    let(:envio) { Crm::MetaAds::ComentariosIa::Rede::Envio.new(ok: true, recipient_id: 'psid-1', message_id: 'mid-9') }

    before { allow(Crm::Entrega).to receive(:new).and_return(instance_double(Crm::Entrega, call: nil)) }

    def comentario(rede, caixa)
      Crm::MetaAds::ComentariosIa::Comentario.new(
        network: rede, account_id: account.id, inbox_id: caixa.id, owner_id: 'dono-1', post_id: '1790', ad_id: nil,
        comment_id: "c-#{rede}", parent_id: nil, from_id: 'psid-1', from_name: 'carla.mendes', text: 'Quanto custa?',
        created_time: 1.minute.ago
      )
    end

    def privado(alvo) = create(:message, conversation: alvo, account: account, inbox: alvo.inbox, message_type: :outgoing, source_id: 'mid-1')

    it 'a que a IA abre para a equipe é da equipe, antes e depois de o cliente escrever, no Instagram e no Facebook',
       :aggregate_failures do
      [['instagram', instagram], ['facebook', pagina]].each do |rede, caixa|
        aberta = conversas.para_voce!(comentario(rede, caixa), care, 'to_you')
        expect(described_class.iniciada_por(aberta.reload)).to eq('equipe'), rede

        chegou = create(:message, conversation: aberta, account: account, inbox: caixa, message_type: :incoming)
        expect(described_class.iniciada_por(aberta.reload)).to eq('equipe'), rede
        expect(described_class.primeira?(chegou)).to be(true), rede
      end
    end

    it 'a nova do privado da IA é da equipe: no Instagram (anotar!) e no Messenger (no_messenger! e anotar!)',
       :aggregate_failures do
      nova = create(:conversation, account: account, inbox: instagram, status: :open)
      privado(nova)
      conversas.anotar!(nova, comentario('instagram', instagram), care, nova: true)
      expect(described_class.iniciada_por(nova.reload)).to eq('equipe')

      messenger = conversas.no_messenger!(comentario('facebook', pagina), envio, care.message, 42)
      conversas.anotar!(messenger, comentario('facebook', pagina), care, nova: true)
      expect(described_class.iniciada_por(messenger.reload)).to eq('equipe')
    end

    it 'a que o cliente já tinha aberta na caixa continua dele depois do privado da IA' do
      dele = create(:conversation, account: account, inbox: instagram, status: :open)
      create(:message, conversation: dele, account: account, inbox: instagram, message_type: :incoming, created_at: 1.hour.ago)
      privado(dele)
      conversas.anotar!(dele, comentario('instagram', instagram), care, nova: false)

      expect(described_class.iniciada_por(dele.reload)).to eq('cliente')
    end

    # O privado da tela não marca a conversa: a primeira mensagem é o privado que saiu.
    it 'a do privado que a pessoa da equipe manda pela tela é da equipe' do
      tela = create(:conversation, account: account, inbox: instagram, status: :open)
      privado(tela)

      expect(described_class.iniciada_por(tela.reload)).to eq('equipe')
    end
  end

  describe 'pelo Valores' do
    let(:valores) { Autonomia::Automacao::Valores }

    it 'lê conversa.iniciada_por e mensagem.primeira, com as opções que o salvar aceita', :aggregate_failures do
      primeira = mensagem(:incoming)
      segunda = mensagem(:outgoing)
      lido = ->(caminho, cada) { valores.new(alvo: conversa.reload, mensagem: cada, quem: nil).ler(caminho) }

      expect(lido.call('conversa.iniciada_por', primeira)).to eq('cliente')
      expect([lido.call('mensagem.primeira', primeira), lido.call('mensagem.primeira', segunda)]).to eq([true, false])
      expect(valores.fechado('mensagem.primeira')['opcoes']).to eq([true, false])
      expect(valores.fechado('conversa.iniciada_por')['opcoes']).to eq(%w[cliente equipe])
    end

    it 'no card, lê quem começou a conversa principal' do
      admin = create(:user, account: account, role: :administrator)
      funil = create_crm_pipeline(account: account, user: admin)
      card = Crm::Card.create!(account: account, pipeline: funil.first, stage: funil.last, title: 'Seguro auto', currency: 'BRL',
                               primary_conversation: conversa, contact: conversa.contact)
      mensagem(:incoming)

      expect(valores.new(alvo: card.reload, quem: nil).ler('conversa.iniciada_por')).to eq('cliente')
    end
  end
end
