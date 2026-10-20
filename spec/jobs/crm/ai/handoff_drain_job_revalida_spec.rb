require 'rails_helper'

# #1975: antes de entregar a espera da IA do CRM, a fila confere com a IA se o problema do cliente segue aberto, mas só
# uma vez, e de novo só quando chega mensagem nova depois da última conferência. As outras esperas seguem como antes.
RSpec.describe Crm::Ai::HandoffDrainJob do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:ana) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, status: :open).reload }
  let(:card) do
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    stage.update!(metadata: { 'ai_handoff' => { 'enabled' => true, 'handoff_mode' => 'r2_direct', 'trigger' => 'pedido de pessoa' } })
    account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: contact, title: 'Pedido', primary_conversation: conversation,
                              inbox: inbox)
  end
  let(:revalida) { instance_double(Crm::Ai::RevalidaPassagem) }

  before do
    create(:inbox_member, inbox: inbox, user: ana)
    card
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return({ ana.id.to_s => 'online' })
    allow(Crm::Ai::RevalidaPassagem).to receive(:new).and_return(revalida)
  end

  after { ActiveRecord::Base.connection.execute('SELECT pg_advisory_unlock_all()') }

  def segurar!(motivo: Crm::Ai::HandoffExecutor::MOTIVO_DA_ENTREGA, razao: 'cliente pediu a cotação e o robô falhou')
    Crm::Entrega::Marca.marcar(conversation, modo: Crm::Entrega::Marca::SEGURANDO, motivo: motivo, falha: 'ninguem_online', razao: razao)
    conversation.save!
  end

  def fala!(texto, tipo: :outgoing, **extra)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: tipo, content: texto, **extra)
  end

  def resposta(passa, motivo)
    { passa: passa, motivo: motivo, decisao: passa ? 'problema_em_aberto' : 'resolvido' }
  end

  def atividades(tipo)
    Crm::Activity.where(card_id: card.id, event_type: tipo)
  end

  it 'resolvido depois da espera: a marca sai, ninguém recebe e o porquê fica no card', :aggregate_failures do
    segurar!
    travel(1.minute) { fala!('Aqui estão as 3 opções da sua cotação.') }
    allow(revalida).to receive(:call).and_return(resposta(false, 'o robô enviou a cotação e o cliente não voltou'))

    described_class.perform_now

    expect(conversation.reload.assignee_id).to be_nil
    expect(Crm::Entrega::Marca.presente?(conversation)).to be(false)
    expect(atividades('ai_handoff_withdrawn').sole.payload).to include('reason' => 'o robô enviou a cotação e o cliente não voltou',
                                                                       'decision' => 'resolvido')
  end

  it 'problema ainda aberto: entrega, com o motivo novo na atividade da entrega', :aggregate_failures do
    segurar!
    travel(1.minute) { fala!('O que é DMH?', tipo: :incoming) }
    allow(revalida).to receive(:call).and_return(resposta(true, 'cliente pediu explicação de DMH e o robô não soube'))

    described_class.perform_now

    expect(conversation.reload.assignee_id).to eq(ana.id)
    expect(atividades('ai_handoff').sole.payload['reason']).to eq('cliente pediu explicação de DMH e o robô não soube')
  end

  # Conversa 327: a avaliação da meia-noite já tinha visto a cotação enviada e pediu a pessoa assim mesmo; nada chegou
  # depois. A releitura antes da entrega, mesmo sem mensagem nova, é o que evita entregá-la horas depois.
  it 'sem mensagem nova depois da espera: relê uma vez e, resolvido, não entrega', :aggregate_failures do
    fala!('Aqui estão as 3 opções da sua cotação.', created_at: 1.minute.ago)
    segurar!
    allow(revalida).to receive(:call).and_return(resposta(false, 'o robô enviou a cotação e o cliente não voltou'))

    described_class.perform_now

    expect(revalida).to have_received(:call).once
    expect(conversation.reload.assignee_id).to be_nil
    expect(Crm::Entrega::Marca.presente?(conversation)).to be(false)
    expect(Crm::Ai::RevalidaPassagem).to have_received(:new)
      .with(conversation, card: card, motivo_do_pedido: 'cliente pediu a cotação e o robô falhou')
  end

  it 'sem mensagem nova e o problema segue aberto: entrega com o motivo novo', :aggregate_failures do
    fala!('mensagem de antes da espera', tipo: :incoming, created_at: 1.minute.ago)
    segurar!
    allow(revalida).to receive(:call).and_return(resposta(true, 'cliente quer falar do sinistro e ninguém respondeu'))

    described_class.perform_now

    expect(conversation.reload.assignee_id).to eq(ana.id)
    expect(atividades('ai_handoff').sole.payload['reason']).to eq('cliente quer falar do sinistro e ninguém respondeu')
  end

  it 'depois de relida, nota privada e atividade não pedem outra releitura', :aggregate_failures do
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return({})
    segurar!
    allow(revalida).to receive(:call).and_return(resposta(true, 'dúvida sem resposta'))

    described_class.perform_now
    expect(Crm::Entrega::Marca.dados(conversation.reload)['revalidado_ate']).to eq(0)

    travel(1.minute) do
      fala!('nota interna', private: true)
      fala!('Conversa atribuída', tipo: :activity)
    end
    described_class.perform_now

    expect(revalida).to have_received(:call).once
  end

  it 'a espera que o próprio agente pediu não é relida' do
    segurar!(motivo: 'robo_pediu')
    travel(1.minute) { fala!('Já resolvi por aqui.') }

    described_class.perform_now

    expect(Crm::Ai::RevalidaPassagem).not_to have_received(:new)
    expect(conversation.reload.assignee_id).to eq(ana.id)
  end

  it 'de pé e ainda sem ninguém online: relê uma vez só por mensagem nova', :aggregate_failures do
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return({})
    segurar!
    duvida = travel(1.minute) { fala!('O que é DMH?', tipo: :incoming) }
    allow(revalida).to receive(:call).and_return(resposta(true, 'dúvida de DMH sem resposta'))

    described_class.perform_now
    described_class.perform_now

    expect(revalida).to have_received(:call).once
    marca = Crm::Entrega::Marca.dados(conversation.reload)
    expect(marca).to include('razao' => 'dúvida de DMH sem resposta', 'revalidado_ate' => duvida.id)

    travel(2.minutes) { fala!('Alguém pode me ajudar?', tipo: :incoming) }
    described_class.perform_now
    expect(revalida).to have_received(:call).twice
  end

  it 'a IA fora do ar: entrega como antes (perder o pedido é pior)' do
    segurar!
    travel(1.minute) { fala!('O que é DMH?', tipo: :incoming) }
    allow(revalida).to receive(:call).and_raise(Crm::Ai::RevalidaPassagem::Indisponivel, 'sem_credencial')

    described_class.perform_now

    expect(conversation.reload.assignee_id).to eq(ana.id)
  end

  it 'passando da cota da rodada, a conversa espera a rodada seguinte sem entregar sem reler', :aggregate_failures do
    stub_const("#{described_class}::REVALIDACOES_POR_RODADA", 0)
    segurar!
    travel(1.minute) { fala!('O que é DMH?', tipo: :incoming) }

    described_class.perform_now

    expect(conversation.reload.assignee_id).to be_nil
    expect(Crm::Entrega::Marca.presente?(conversation)).to be(true)
  end

  # Revisão do PR #1980 (HIGH 1): a resposta é sobre a conversa que foi lida. Um pedido explícito que chega durante
  # a chamada não some com um "resolvido" velho: nada é gravado, ninguém recebe agora e a rodada seguinte relê.
  it 'pedido do cliente chega durante a releitura: a resposta velha é descartada e a espera fica', :aggregate_failures do
    segurar!
    allow(revalida).to receive(:call) do
      fala!('Quero falar com uma pessoa, por favor', tipo: :incoming)
      resposta(false, 'o robô enviou a cotação')
    end

    described_class.perform_now

    expect(conversation.reload.assignee_id).to be_nil
    marca = Crm::Entrega::Marca.dados(conversation)
    expect(marca).to include('razao' => 'cliente pediu a cotação e o robô falhou')
    expect(marca).not_to have_key('revalidado_ate')
    expect(atividades('ai_handoff_withdrawn')).to be_empty
  end

  it 'o motivo da espera muda durante a releitura: a resposta velha é descartada', :aggregate_failures do
    segurar!
    allow(revalida).to receive(:call) do
      Crm::Entrega::Marca.marcar(conversation, modo: Crm::Entrega::Marca::SEGURANDO, motivo: 'ia_crm', razao: 'pedido novo')
      conversation.save!
      resposta(false, 'resolvido antes')
    end

    described_class.perform_now

    expect(Crm::Entrega::Marca.dados(conversation.reload)).to include('razao' => 'pedido novo')
    expect(atividades('ai_handoff_withdrawn')).to be_empty
  end

  # HIGH 2: qualquer falha entrega como hoje, já nesta rodada, e não paga outra chamada sem mensagem nova.
  it 'falha repetida não chama o modelo duas vezes', :aggregate_failures do
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return({})
    segurar!
    allow(revalida).to receive(:call).and_raise(Crm::Ai::ResponsesClient::Error, 'timeout')

    described_class.perform_now
    described_class.perform_now

    expect(revalida).to have_received(:call).once
    expect(Crm::Entrega::Marca.dados(conversation.reload)).to include('revalidado_ate' => 0,
                                                                      'razao' => 'cliente pediu a cotação e o robô falhou')
  end

  it 'erro inesperado ao montar o contexto entrega a conversa como hoje' do
    allow(Crm::Ai::RevalidaPassagem).to receive(:new).and_call_original
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: 'chave'))
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(instance_double(Crm::Ai::ResponsesClient))
    allow(Crm::Ai::ContextBuilder).to receive(:new).and_raise(NoMethodError, 'quebrou')
    segurar!

    described_class.perform_now

    expect(conversation.reload.assignee_id).to eq(ana.id)
  end

  it 'a releitura que falha não gasta a cota: com cota 1, a terceira conversa ainda é relida e entregue', :aggregate_failures do
    stub_const("#{described_class}::REVALIDACOES_POR_RODADA", 1)
    conversas = [conversation] + Array.new(2) do
      create(:conversation, account: account, inbox: inbox, contact: create(:contact, account: account), status: :open).reload
    end
    conversas.each do |conversa|
      Crm::Entrega::Marca.marcar(conversa, modo: Crm::Entrega::Marca::SEGURANDO, motivo: 'ia_crm', razao: 'pedido')
      conversa.save!
    end
    chamadas = 0
    allow(revalida).to receive(:call) do
      chamadas += 1
      raise Crm::Ai::ResponsesClient::Error, 'timeout' if chamadas <= 2

      resposta(true, 'segue aberto')
    end

    described_class.perform_now

    expect(chamadas).to eq(3)
    expect(conversas.map { |conversa| conversa.reload.assignee_id }).to all(eq(ana.id))
  end

  # MEDIUM: a releitura só começa se cabe inteira no que sobra da rodada; senão, fica para a seguinte, sem entregar.
  it 'sem tempo na rodada para uma releitura inteira, a conversa espera a rodada seguinte', :aggregate_failures do
    stub_const("#{described_class}::RODADA_MAXIMA", Crm::Ai::RevalidaPassagem::TIMEOUT)
    segurar!

    described_class.perform_now

    expect(Crm::Ai::RevalidaPassagem).not_to have_received(:new)
    expect(conversation.reload.assignee_id).to be_nil
    expect(Crm::Entrega::Marca.presente?(conversation)).to be(true)
  end
end
