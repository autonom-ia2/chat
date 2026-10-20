require 'rails_helper'

# #1693 × #1694: o convite feito pela regra de um assunto fora do foco não esquece o assunto quando vence. Foco no
# "Seguro auto" (Vendas, quem cuida: Bruno). O João escreve "quero falar com alguém sobre o sinistro": a regra de
# Sinistros convida; quem foi convidado deixa vencer; a fila roda de novo pela regra de Sinistros, e não pela do foco.
RSpec.describe 'Convite vencido pela regra do card do pedido' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Adm Conta') }
  let(:ana) { create(:user, account: account, role: :agent, name: 'Ana Sinistros') }
  let(:carla) { create(:user, account: account, role: :agent, name: 'Carla Sinistros') }
  let(:bruno) { create(:user, account: account, role: :agent, name: 'Bruno Vendas') }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:contact) { create(:contact, account: account) }
  let(:conversa) { create(:conversation, account: account, inbox: inbox, contact: contact, status: :open, assignee: nil).reload }
  let(:vendas) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let(:sinistros) { create_crm_pipeline(account: account, user: admin, name: 'Sinistros') }
  let!(:sinistro) { card(sinistros, 'Sinistro do carro', 2.minutes.ago) }
  let(:pedido) { { intent: 'transferir', should_handoff: true, reason: 'Pediu atendente', suggested_agent: nil } }

  around do |example|
    with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true') { example.run }
  end

  before do
    admin
    allow(Rails.configuration.dispatcher).to receive(:dispatch)
    [ana, carla, bruno].each { |user| create(:inbox_member, inbox: inbox, user: user) }
    acesso(ana, sinistros)
    acesso(bruno, vendas)
    [vendas, sinistros].each do |(_pipeline, stage)|
      stage.update!(metadata: { 'ai_handoff' => { 'enabled' => true, 'handoff_mode' => 'r3_invite', 'invite_ttl_seconds' => 3600 } })
    end
    online(ana, carla, bruno)
    card(vendas, 'Seguro auto', 1.minute.ago) # o foco, em Vendas
  end

  after { ActiveRecord::Base.connection.execute('SELECT pg_advisory_unlock_all()') }

  def online(*users)
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return(users.to_h { |user| [user.id.to_s, 'online'] })
  end

  def acesso(user, (pipeline, _stage))
    Crm::InboxAgentAccess.create!(account: account, inbox: inbox, user: user, all_pipelines: false)
                         .agent_pipelines.create!(account: account, pipeline: pipeline)
  end

  def card((pipeline, stage), titulo, focused_at)
    account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: contact, title: titulo, inbox: inbox,
                              primary_conversation: conversa).tap do |card|
      Crm::CardConversation.find_or_create_by!(account: account, card: card, conversation: conversa).update!(focused_at: focused_at)
    end
  end

  def marca
    Crm::Entrega::Marca.dados(conversa.reload)
  end

  def pedir_pelo_sinistro
    Crm::Ai::HandoffExecutor.new(card: sinistro, handoff: pedido, pelo_card: true).perform
  end

  # A continuação da espera da IA do CRM passa pela releitura (#1975): a fila segura, relê (aqui, com o problema
  # aberto) e só então segue a regra.
  def deixa_vencer_e_rele(horas)
    releitura = instance_double(Crm::Ai::RevalidaPassagem, call: { passa: true, motivo: 'segue aberto', decisao: 'problema_em_aberto' })
    allow(Crm::Ai::RevalidaPassagem).to receive(:new).and_return(releitura)
    inicio = horas.hours.from_now
    travel_to(inicio) { Crm::Ai::HandoffDrainJob.perform_now }
    travel_to(inicio + 2.minutes) do
      Crm::Ai::HandoffDrainJob.perform_now
      Crm::Ai::RevalidaPassagemJob.perform_now(conversa.id, marca['revalidando_desde'])
    end
    travel_to(inicio + 4.minutes) { Crm::Ai::HandoffDrainJob.perform_now }
  end

  # Só a Ana cuida de Sinistros: sem convite novo, a conversa vai a quem cuida de Sinistros e está online (#1694), a Ana.
  it 'a Ana de Sinistros deixa vencer: o Bruno de Vendas NÃO recebe, e a conversa segue pela regra de Sinistros',
     :aggregate_failures do
    acesso(carla, vendas)
    pedir_pelo_sinistro
    expect(marca).to include('modo' => Crm::Entrega::Marca::CONVITE, 'convidado_id' => ana.id, 'card_id' => sinistro.id)

    deixa_vencer_e_rele(7)

    expect(conversa.reload.assignee_id).to eq(ana.id)
  end

  it 'com a Carla também em Sinistros: ela é convidada depois da Ana, nunca o Bruno', :aggregate_failures do
    acesso(carla, sinistros)
    pedir_pelo_sinistro
    primeira = marca['convidado_id']
    expect([ana.id, carla.id]).to include(primeira)

    deixa_vencer_e_rele(7)

    expect(marca).to include('modo' => Crm::Entrega::Marca::CONVITE, 'venceram' => [primeira], 'card_id' => sinistro.id)
    expect(marca['convidado_id']).to eq(([ana.id, carla.id] - [primeira]).first)
  end

  describe 'convite vencido sem convidado_id na marca' do
    # A marca de um convite pela regra do card do pedido, vencida, sem quem foi convidado gravado.
    def convite_vencido_sem_convidado
      Crm::Entrega::Marca.marcar(conversa, modo: Crm::Entrega::Marca::CONVITE, motivo: 'ia_crm', ate: 1.hour.ago, card: sinistro)
      conversa.save!
    end

    def convidou_no_card(card, pessoa)
      card.update!(metadata: { 'ai' => { 'handoff' => { 'invited_agent_id' => pessoa.id } } })
    end

    it 'quem deixou vencer vem do card do pedido, e não do card em foco' do
      convidou_no_card(sinistro, ana)
      convidou_no_card(account.crm_cards.find_by!(title: 'Seguro auto'), bruno)
      convite_vencido_sem_convidado
      allow(Crm::Entrega).to receive(:new).and_call_original

      Crm::Entrega::ConviteVencido.new(conversa.reload).call

      expect(Crm::Entrega).to have_received(:new).with(hash_including(excluir: [ana.id], card: sinistro, pelo_card: true))
    end

    it 'sem saber quem foi convidado: a marca sai e a regra não roda de novo (ninguém é reconvidado)', :aggregate_failures do
      convite_vencido_sem_convidado
      allow(Crm::Entrega).to receive(:new).and_call_original

      Crm::Entrega::ConviteVencido.new(conversa.reload).call

      expect(Crm::Entrega).not_to have_received(:new)
      expect(marca).to be_nil
    end
  end
end
