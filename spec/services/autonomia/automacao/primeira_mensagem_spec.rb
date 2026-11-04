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

  describe 'pelo Valores' do
    let(:valores) { Autonomia::Automacao::Valores }

    it 'lê conversa.iniciada_por e mensagem.primeira, com as opções que o salvar aceita', :aggregate_failures do
      primeira = mensagem(:incoming)
      segunda = mensagem(:outgoing)
      lido = ->(caminho, cada) { valores.new(alvo: conversa.reload, mensagem: cada).ler(caminho) }

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

      expect(valores.new(alvo: card.reload).ler('conversa.iniciada_por')).to eq('cliente')
    end
  end
end
