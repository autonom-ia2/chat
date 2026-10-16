require 'rails_helper'

# Convite que vence avisa os administradores (#1140, decisão 8): a IA do CRM convidou a Ana e ninguém pegou no prazo do
# convite. A fila (HandoffDrainJob) tira a marca e avisa os administradores da caixa, com o mesmo aviso do convite que
# nem saiu (Crm::Entrega::AvisoSemNinguem): notificação e atividade no card, uma vez só.
RSpec.describe Crm::Entrega::AvisoSemNinguem do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Adm Caixa') }
  let(:ana) { create(:user, account: account, role: :agent, name: 'Ana') }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:bot) { create(:agent_bot, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:vendas) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let(:conversa) do
    create(:conversation, account: account, inbox: inbox, contact: contact, status: :open).reload.tap do |conversation|
      conversation.update!(ai_assignee: bot, assignee: nil)
    end
  end
  let!(:card) do
    account.crm_cards.create!(pipeline: vendas.first, stage: vendas.last, contact: contact, title: 'Vendas',
                              primary_conversation: conversa, inbox: inbox)
  end

  before do
    create(:agent_bot_inbox, inbox: inbox, agent_bot: bot)
    [admin, ana].each { |user| create(:inbox_member, inbox: inbox, user: user) }
    vendas.last.update!(metadata: { 'ai_handoff' => { 'enabled' => true, 'handoff_mode' => 'r3_invite', 'invite_ttl_seconds' => 3600 } })
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return({ ana.id.to_s => 'online' })
    conversa.bot_handoff!
  end

  after { ActiveRecord::Base.connection.execute('SELECT pg_advisory_unlock_all()') }

  def avisos_ao_admin
    Notification.where(user: admin, notification_type: :conversation_handoff_request).count
  end

  def atividades_de_aviso
    card.activities.where(event_type: described_class::EVENTO)
  end

  # Pega: o convite vencia e ninguém sabia que a conversa ficou sem pessoa.
  it 'convite vencido: tira a marca e avisa os administradores da caixa uma vez só', :aggregate_failures do
    expect(Crm::Entrega::Marca.dados(conversa.reload)).to include('modo' => Crm::Entrega::Marca::CONVITE)

    travel 2.hours do
      Crm::Ai::HandoffDrainJob.perform_now
      Crm::Ai::HandoffDrainJob.perform_now
    end

    expect(Crm::Entrega::Marca.dados(conversa.reload)).to be_nil
    expect(avisos_ao_admin).to eq(1)
    expect(atividades_de_aviso.count).to eq(1)
    expect(atividades_de_aviso.first.payload).to include('reason' => described_class::CONVITE_VENCIDO)
  end

  # Pega: avisar no meio do prazo, com o convite ainda valendo.
  it 'convite no prazo: não avisa' do
    travel 30.minutes do
      Crm::Ai::HandoffDrainJob.perform_now
    end

    expect(avisos_ao_admin).to eq(0)
  end

  # Pega: avisar de um convite que a Ana pegou (a marca sai na atribuição).
  it 'Ana pegou antes de vencer: não avisa', :aggregate_failures do
    conversa.reload.update!(assignee: ana)

    travel 2.hours do
      Crm::Ai::HandoffDrainJob.perform_now
    end

    expect(avisos_ao_admin).to eq(0)
    expect(atividades_de_aviso.count).to eq(0)
  end

  # Pega: a atribuição que chega entre a consulta da fila e a trava (a marca ainda está lá) gerar aviso e tirar a marca.
  it 'alguém pega entre a consulta e a trava: não avisa', :aggregate_failures do
    original = Crm::Entrega::Marca.method(:convite_vencido?)
    chamadas = 0
    allow(Crm::Entrega::Marca).to receive(:convite_vencido?) do |*argumentos, **opcoes|
      chamadas += 1
      Conversation.where(id: conversa.id).update_all(assignee_id: ana.id) if chamadas == 1 # rubocop:disable Rails/SkipsModelValidations
      original.call(*argumentos, **opcoes)
    end

    travel 2.hours do
      Crm::Ai::HandoffDrainJob.perform_now
    end

    expect(conversa.reload.assignee_id).to eq(ana.id)
    expect(avisos_ao_admin).to eq(0)
  end

  # Pega: a adiada perder a marca (ela volta à fila quando reabre) e gerar aviso.
  it 'conversa adiada depois da consulta: guarda a marca e não avisa', :aggregate_failures do
    original = Crm::Entrega::Marca.method(:convite_vencido?)
    chamadas = 0
    allow(Crm::Entrega::Marca).to receive(:convite_vencido?) do |*argumentos, **opcoes|
      chamadas += 1
      Conversation.where(id: conversa.id).update_all(status: Conversation.statuses[:snoozed]) if chamadas == 1 # rubocop:disable Rails/SkipsModelValidations
      original.call(*argumentos, **opcoes)
    end

    travel 2.hours do
      Crm::Ai::HandoffDrainJob.perform_now
    end

    expect(Crm::Entrega::Marca.dados(conversa.reload)).to include('modo' => Crm::Entrega::Marca::CONVITE)
    expect(avisos_ao_admin).to eq(0)
  end

  # Pega: uma falha no aviso desfazer a saída da marca e prender a conversa fora do rodízio, tentada a cada rodada.
  it 'aviso falha: a marca sai mesmo assim e o erro vai para o rastreador', :aggregate_failures do
    allow(NotificationBuilder).to receive(:new).and_raise(ActiveRecord::RecordInvalid)
    allow(ChatwootExceptionTracker).to receive(:new).and_call_original

    travel 2.hours do
      Crm::Ai::HandoffDrainJob.perform_now
    end

    expect(Crm::Entrega::Marca.dados(conversa.reload)).to be_nil
    expect(ChatwootExceptionTracker).to have_received(:new)
  end

  # Pega: caixa sem administrador membro deixar o aviso sem destino (vale a conta, como no convite que nem saiu).
  it 'caixa sem administrador: avisa os administradores da conta' do
    InboxMember.find_by(inbox: inbox, user: admin).destroy!

    travel 2.hours do
      Crm::Ai::HandoffDrainJob.perform_now
    end

    expect(avisos_ao_admin).to eq(1)
  end
end
