require 'rails_helper'

# Convite vencido convida outra pessoa (#1694, decisão do Rodrigo de 16/10, opção "a"): o robô pediu pessoa, a regra
# convidou a Ana e ela deixou vencer. A regra roda de novo deixando de fora quem já deixou vencer (guardado na marca do
# motor). Sem ninguém que sobre, a conversa segura esperando alguém online, sem convite novo. O aviso aos administradores
# sai uma vez só na espera, e não a cada convite vencido.
RSpec.describe 'Convite vencido convida outra pessoa' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Adm Conta') }
  let(:ana) { create(:user, account: account, role: :agent, name: 'Ana') }
  let(:bruno) { create(:user, account: account, role: :agent, name: 'Bruno') }
  let(:carla) { create(:user, account: account, role: :agent, name: 'Carla') }
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
    admin
    create(:agent_bot_inbox, inbox: inbox, agent_bot: bot)
    [ana, bruno, carla].each { |user| create(:inbox_member, inbox: inbox, user: user) }
    vendas.last.update!(metadata: { 'ai_handoff' => { 'enabled' => true, 'handoff_mode' => 'r3_invite', 'invite_ttl_seconds' => 3600 } })
    online(ana)
    conversa.bot_handoff!
  end

  after { ActiveRecord::Base.connection.execute('SELECT pg_advisory_unlock_all()') }

  def online(*users)
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return(users.to_h { |user| [user.id.to_s, 'online'] })
  end

  def convidada
    card.reload.metadata.dig('ai', 'handoff', 'invited_agent_id')
  end

  def marca
    Crm::Entrega::Marca.dados(conversa.reload)
  end

  def avisos_ao_admin
    Notification.where(user: admin, notification_type: :conversation_handoff_request).count
  end

  # Passa o prazo do convite e o intervalo entre convites (6 h), e roda a fila.
  def deixa_vencer(horas)
    travel_to(horas.hours.from_now) { Crm::Ai::HandoffDrainJob.perform_now }
  end

  # Pega: a regra convidava de novo a mesma pessoa que deixou vencer, e o aviso saía a cada ciclo. Só quem deve ser
  # convidado em cada passo está online: o rodízio não decide o teste.
  it 'Ana deixa vencer: o Bruno é convidado e sai um aviso; o Bruno deixa vencer: a Carla, sem segundo aviso', :aggregate_failures do
    expect(convidada).to eq(ana.id)

    online(ana, bruno)
    deixa_vencer(7)
    expect(convidada).to eq(bruno.id)
    expect(marca).to include('modo' => Crm::Entrega::Marca::CONVITE, 'venceram' => [ana.id])
    expect(avisos_ao_admin).to eq(1)

    online(ana, bruno, carla)
    deixa_vencer(14)
    expect(convidada).to eq(carla.id)
    expect(marca).to include('modo' => Crm::Entrega::Marca::CONVITE, 'venceram' => [ana.id, bruno.id])
    expect(avisos_ao_admin).to eq(1)
  end

  # Pega: depois de todos deixarem vencer, a regra convidava de novo alguém que já tinha deixado vencer.
  it 'todos deixam vencer, ninguém online: segura sem convite novo e sem outro aviso', :aggregate_failures do
    online(ana, bruno)
    deixa_vencer(7)
    online(ana, bruno, carla)
    deixa_vencer(14)
    expect(convidada).to eq(carla.id)

    online
    deixa_vencer(21)
    deixa_vencer(28)

    expect(marca).to include('modo' => Crm::Entrega::Marca::SEGURANDO, 'falha' => 'ninguem_online',
                             'venceram' => [ana.id, bruno.id, carla.id])
    expect(card.reload.metadata.dig('ai', 'handoffs').size).to eq(3)
    expect(conversa.reload).to have_attributes(assignee_id: nil, ai_assignee: bot)
    expect(conversa).to be_bot_handoff_waiting
    expect(avisos_ao_admin).to eq(1)
  end

  # Promessa ao Rodrigo (opção "a"): todos deixaram vencer, a conversa vai para o PRIMEIRO que ficar online, inclusive
  # quem deixou vencer, sem convite novo e sem esperar o espaçamento de 30 minutos.
  it 'todos deixaram vencer: a Ana fica online e recebe a conversa na rodada seguinte', :aggregate_failures do
    online(ana, bruno)
    deixa_vencer(7)
    online(ana, bruno, carla)
    deixa_vencer(14)
    online
    deixa_vencer(21)
    expect(conversa.reload.assignee_id).to be_nil

    online(ana)
    travel_to(21.hours.from_now + 2.minutes) { Crm::Ai::HandoffDrainJob.perform_now }

    expect(conversa.reload).to have_attributes(assignee_id: ana.id, ai_assignee: nil)
    expect(marca).to be_nil
    expect(card.reload.metadata.dig('ai', 'handoffs').size).to eq(3)
  end

  # Pega: a marca de convite gravada antes do #1694 (sem convidado_id) reconvidar quem deixou vencer: vale o ciclo do card.
  it 'marca antiga sem convidado: a convidada sai pelo ciclo do card', :aggregate_failures do
    antiga = Crm::Entrega::Marca.dados(conversa.reload).except('convidado_id')
    Conversation.where(id: conversa.id).update_all( # rubocop:disable Rails/SkipsModelValidations
      ['additional_attributes = jsonb_set(additional_attributes, ?, ?::jsonb)', "{#{Crm::Entrega::Marca::CHAVE}}", antiga.to_json]
    )
    online(ana, bruno)

    deixa_vencer(7)

    expect(convidada).to eq(bruno.id)
    expect(marca).to include('venceram' => [ana.id])
  end

  # Pega: o aviso que falhou contar como dado (avisado_em gravado) e a espera nunca avisar os administradores.
  it 'aviso que falha não conta: o convite seguinte que vence avisa', :aggregate_failures do
    online(ana, bruno)
    allow(NotificationBuilder).to receive(:new).and_call_original
    allow(NotificationBuilder).to receive(:new).with(hash_including(user: admin)).and_raise(ActiveRecord::RecordInvalid)
    deixa_vencer(7)
    expect(convidada).to eq(bruno.id)
    expect(marca['avisado_em']).to be_nil

    allow(NotificationBuilder).to receive(:new).and_call_original
    online(ana, bruno, carla)
    deixa_vencer(14)

    expect(avisos_ao_admin).to eq(1)
    expect(marca['avisado_em']).to be_present
  end

  # Pega: o primeiro online que deixou vencer não ser o primeiro da lista (o Bruno, e não a Ana).
  it 'todos deixaram vencer: o Bruno fica online e recebe', :aggregate_failures do
    online(ana, bruno)
    deixa_vencer(7)
    online(ana, bruno, carla)
    deixa_vencer(14)
    online
    deixa_vencer(21)

    online(bruno)
    travel_to(21.hours.from_now + 2.minutes) { Crm::Ai::HandoffDrainJob.perform_now }

    expect(conversa.reload.assignee_id).to eq(bruno.id)
  end

  # Pega: a pessoa fixa da regra ("A mesma pessoa") que deixou vencer prender a conversa enquanto outro de quem cuida está
  # online.
  it 'pessoa fixa deixou vencer e todos também: quem cuida e fica online recebe' do
    vendas.last.update!(metadata: { 'ai_handoff' => { 'enabled' => true, 'handoff_mode' => 'r3_invite', 'invite_ttl_seconds' => 3600,
                                                      'pool_type' => 'user', 'pool_id' => ana.id } })
    InboxMember.where(inbox: inbox, user: [carla]).destroy_all
    online(ana, bruno)
    deixa_vencer(7)
    online
    deixa_vencer(14)

    online(bruno)
    travel_to(14.hours.from_now + 2.minutes) { Crm::Ai::HandoffDrainJob.perform_now }

    expect(conversa.reload.assignee_id).to eq(bruno.id)
  end

  # Pega: a espera sem ninguém na fila (todos saíram da caixa) depois de convites vencidos rodar a entrega inteira a cada
  # 2 minutos, para sempre. Espaça; quem passar a cuidar do funil recebe na tentativa seguinte.
  it 'ninguém na fila depois do vencimento: a fila espaça e o Davi, que entrou na caixa, é convidado', :aggregate_failures do
    InboxMember.where(inbox: inbox, user: [bruno, carla]).destroy_all
    online
    deixa_vencer(7)
    InboxMember.where(inbox: inbox, user: ana).destroy_all
    deixa_vencer(14)
    expect(marca).to include('modo' => Crm::Entrega::Marca::SEGURANDO, 'venceram' => [ana.id])
    expect(Crm::Entrega::ConviteVencido::SEM_NINGUEM).to include(marca['falha'])
    segurada = marca.except('tentado_em')

    davi = create(:user, account: account, role: :agent, name: 'Davi')
    create(:inbox_member, inbox: inbox, user: davi)
    online(davi)
    allow(Crm::Entrega).to receive(:new).and_call_original

    travel_to(14.hours.from_now + 10.minutes) { Crm::Ai::HandoffDrainJob.perform_now }
    expect(Crm::Entrega).not_to have_received(:new)
    expect(marca.except('tentado_em')).to eq(segurada)

    travel_to(14.hours.from_now + Crm::Entrega::ConviteVencido::ESPERA_SEM_NINGUEM + 1.minute) { Crm::Ai::HandoffDrainJob.perform_now }
    expect(convidada).to eq(davi.id)
  end

  # Pega: a espera sem ninguém na fila (ninguém cuida do funil) com quem já deixou vencer rodar a entrega inteira a cada 2
  # minutos, para sempre. Segurar por presença não espaça: quem fica online recebe na rodada seguinte.
  it 'espaçamento: só a espera sem ninguém na fila, e só dentro do intervalo', :aggregate_failures do
    sem_ninguem = { 'venceram' => [ana.id], 'falha' => 'ninguem_cuida', 'decidido_em' => 10.minutes.ago.iso8601 }
    espaca = ->(marca) { Crm::Entrega::ConviteVencido.espacar?(marca) }

    expect(espaca.call(sem_ninguem)).to be(true)
    expect(espaca.call(sem_ninguem.merge('decidido_em' => 31.minutes.ago.iso8601))).to be(false)
    expect(espaca.call(sem_ninguem.merge('falha' => 'ninguem_online'))).to be(false)
    expect(espaca.call(sem_ninguem.except('venceram'))).to be(false)
  end
end
