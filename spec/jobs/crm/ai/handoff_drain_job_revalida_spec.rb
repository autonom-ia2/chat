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
end
