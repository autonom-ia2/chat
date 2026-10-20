require 'rails_helper'

# #1975: a reavaliação isolada ("o problema do cliente foi resolvido?"). Uma chamada, sem efeito colateral.
RSpec.describe Crm::Ai::RevalidaPassagem do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, status: :open) }
  let(:client) { instance_double(Crm::Ai::ResponsesClient) }
  let(:enviado) { {} }
  let(:resolvido) { [{ pedido: 'cotação do seguro', situacao: 'resolvido', como: 'o atendente enviou a cotação' }] }

  before do
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    stage.update!(metadata: { 'ai_handoff' => { 'enabled' => true, 'trigger' => 'quando o atendente informar que vai encaminhar' } })
    account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: contact, title: 'Cotação', primary_conversation: conversation,
                              inbox: inbox)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'Quero uma cotação')
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: 'chave'))
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
  end

  def responde(json)
    allow(client).to receive(:create) do |**args|
      enviado.merge!(args)
      { text: { pedidos: resolvido }.merge(json).to_json }
    end
  end

  it 'resolvido: não passa, com o motivo do modelo', :aggregate_failures do
    responde(decisao: 'resolvido', motivo: 'o atendente enviou a cotação')

    expect(described_class.new(conversation).call).to eq(passa: false, motivo: 'o atendente enviou a cotação', decisao: 'resolvido')
    entrada = JSON.parse(enviado[:input])
    expect(entrada['recent_messages'].map { |m| m['content'] }).to include('Quero uma cotação')
    expect(entrada['handoff_trigger']).to eq('quando o atendente informar que vai encaminhar')
    expect(enviado[:schema][:name]).to eq('passagem_revalidada')
  end

  it 'pedido de pessoa e problema em aberto passam', :aggregate_failures do
    responde(decisao: 'pedido_de_pessoa', motivo: 'cliente pediu um atendente')
    expect(described_class.new(conversation).call[:passa]).to be(true)

    responde(decisao: 'problema_em_aberto', motivo: 'cliente pediu explicação de DMH e o robô não soube')
    expect(described_class.new(conversation, motivo_do_pedido: 'anúncio de encaminhamento').call)
      .to include(passa: true, motivo: 'cliente pediu explicação de DMH e o robô não soube')
    expect(JSON.parse(enviado[:input])['motivo_do_pedido']).to eq('anúncio de encaminhamento')
  end

  # Backteste v2: o modelo julgava só o último assunto. O inventário de pedidos vem ANTES da decisão no schema (o
  # modelo escreve na ordem), obrigatório, com a situação de cada pedido.
  it 'o schema pede o inventário de pedidos antes da decisão', :aggregate_failures do
    schema = described_class::SCHEMA[:schema]

    expect(schema[:properties].keys.first).to eq(:pedidos)
    expect(schema[:required]).to eq(%w[pedidos decisao motivo])
    expect(schema[:properties][:pedidos]).to include(type: 'array', maxItems: 8)
    expect(schema.dig(:properties, :pedidos, :items, :properties, :situacao, :enum))
      .to eq(%w[resolvido falhou_sem_solucao aguardando_cliente em_andamento])
  end

  # Decisão do Rodrigo (20/10): o modelo lê a conversa inteira; pedido que falhou com pessoa prometida e aviso de espera
  # seguem abertos; esperar a resposta do cliente não pede pessoa, mas não anula um pedido antigo sem solução.
  it 'as instruções levam o inventário e as regras do que fica aberto', :aggregate_failures do
    responde(decisao: 'problema_em_aberto', motivo: 'recotação falhou e ninguém da equipe resolveu')

    described_class.new(conversation).call

    expect(enviado[:instructions]).to equal(described_class::INSTRUCTIONS)
    expect(described_class::INSTRUCTIONS).to include('leia a conversa inteira', 'liste TODOS os pedidos',
                                                     'abandonado não é pedido resolvido',
                                                     'Aviso de espera não resolve o problema',
                                                     'SÓ quando todos os pedidos da lista estão')
  end

  it 'o inventário vai ao log só em contagens, e marca o "resolvido" que a própria lista contradiz', :aggregate_failures do
    pedidos = [{ pedido: 'recotação do carro', situacao: 'falhou_sem_solucao', como: 'o sistema não cotou' },
               { pedido: 'renovação do outro carro', situacao: 'resolvido', como: 'o robô renovou' }]
    responde(pedidos: pedidos, decisao: 'resolvido', motivo: 'o robô renovou o seguro')
    linhas = []
    allow(Rails.logger).to receive(:info) { |linha| linhas << linha }

    described_class.new(conversation).call

    linha = linhas.find { |l| l.include?('[crm][revalida]') }
    expect(linha).to include('decisao=resolvido', 'falhou_sem_solucao:1', 'resolvido:1', 'incoerente=1')
    expect(linha).not_to include('recotação', 'renovação')
  end

  it 'resposta fora do schema levanta, para quem chama decidir', :aggregate_failures do
    responde(decisao: 'talvez', motivo: '')
    expect { described_class.new(conversation).call }.to raise_error(Crm::Ai::RevalidaPassagem::RespostaInvalida)

    responde(pedidos: nil, decisao: 'resolvido', motivo: '')
    expect { described_class.new(conversation).call }.to raise_error(Crm::Ai::RevalidaPassagem::RespostaInvalida)
  end

  it 'sem a IA ligada levanta Indisponivel, sem chamar o modelo' do
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(false)

    expect { described_class.new(conversation).call }.to raise_error(Crm::Ai::RevalidaPassagem::Indisponivel)
    expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
  end

  it 'sem card: passa, como antes, sem chamar o modelo' do
    sem_card = create(:conversation, account: account, inbox: inbox, contact: create(:contact, account: account))

    expect(described_class.new(sem_card).call).to include(passa: true, decisao: 'sem_card')
    expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
  end
end
