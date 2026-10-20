require 'rails_helper'

# #1693, decisão 1a do Rodrigo (16/10): com dois assuntos e um pedido de atendente, vale a regra do assunto a que o
# cliente ligou o pedido (o card em que a IA o pôs), e não a do assunto em foco. Do executor da IA do CRM ao motor de
# entrega, e na fila de quem espera.
RSpec.describe Crm::Entrega do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:ana) { create(:user, account: account, role: :agent, name: 'Ana Vendas') }
  let(:bruno) { create(:user, account: account, role: :agent, name: 'Bruno Sinistro') }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:contact) { create(:contact, account: account) }
  let(:conversa) { create(:conversation, account: account, inbox: inbox, contact: contact, status: :open, assignee: nil).reload }
  let(:vendas) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let(:pos_venda) { create_crm_pipeline(account: account, user: admin, name: 'Pós-venda') }
  let!(:sinistro) { card(pos_venda, 'Sinistro do carro', 2.minutes.ago) }
  let!(:residencial) { card(vendas, 'Seguro residencial', 1.minute.ago) }

  around do |example|
    with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true') { example.run }
  end

  before do
    allow(Rails.configuration.dispatcher).to receive(:dispatch)
    [ana, bruno].each { |user| create(:inbox_member, inbox: inbox, user: user) }
    online(ana, bruno)
    regra!(vendas, ana)
    regra!(pos_venda, bruno)
  end

  def online(*users)
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return(users.to_h { |user| [user.id.to_s, 'online'] })
  end

  # A regra do funil: a pessoa fixa recebe.
  def regra!((_pipeline, stage), pessoa)
    stage.update!(metadata: { 'ai_handoff' => { 'enabled' => true, 'handoff_mode' => 'r2_direct', 'pool_type' => 'user',
                                                'pool_id' => pessoa.id } })
  end

  def card((pipeline, stage), titulo, focused_at)
    account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: contact, title: titulo, inbox: inbox,
                              primary_conversation: conversa).tap do |card|
      Crm::CardConversation.find_or_create_by!(account: account, card: card, conversation: conversa).update!(focused_at: focused_at)
    end
  end

  def pedido
    { intent: 'transferir', should_handoff: true, reason: 'Pediu atendente', suggested_agent: nil }
  end

  it 'o pedido ligado ao sinistro vai pela regra do sinistro, com o residencial em foco' do
    expect(Crm::Assunto.funil_atual(conversa)).to eq(residencial)

    Crm::Ai::HandoffExecutor.new(card: sinistro, handoff: pedido, pelo_card: true).perform

    expect(conversa.reload.assignee_id).to eq(bruno.id)
  end

  it 'sem pelo_card, o card fora do foco não passa a conversa (como antes)' do
    resultado = Crm::Ai::HandoffExecutor.new(card: sinistro, handoff: pedido).perform

    expect(resultado.error).to eq('assunto_mudou')
    expect(conversa.reload.assignee_id).to be_nil
  end

  it 'card do pedido que fechou no meio: vale o assunto em foco' do
    sinistro.update!(status: :lost, closed_at: Time.current)

    allow(Rails.logger).to receive(:info).and_call_original

    Crm::Ai::HandoffExecutor.new(card: sinistro, handoff: pedido, pelo_card: true).perform

    expect(conversa.reload.assignee_id).to eq(ana.id)
    expect(Rails.logger).to have_received(:info).with(a_string_including('desfecho=desvio').and(including('motivo=pedido_card_fechado_foco')))
  end

  it 'convite pela regra do card do pedido: a marca guarda o card, para a fila seguir a mesma regra quando vencer' do
    pos_venda.last.update!(metadata: { 'ai_handoff' => { 'enabled' => true, 'handoff_mode' => 'r3_invite', 'pool_type' => 'user',
                                                         'pool_id' => bruno.id } })

    Crm::Ai::HandoffExecutor.new(card: sinistro, handoff: pedido, pelo_card: true).perform

    expect(Crm::Entrega::Marca.dados(conversa.reload)).to include('modo' => 'convite', 'card_id' => sinistro.id)
  end

  it 'segurada até alguém ficar online, a fila tenta de novo pela regra do card do pedido' do
    online
    described_class.new(conversation: conversa, card: sinistro, motivo: 'ia_crm', origem: 'message', pelo_card: true).call
    expect(Crm::Entrega::Marca.dados(conversa.reload)).to include('modo' => 'segurando', 'card_id' => sinistro.id)

    # A espera já relida (#1975): a fila entrega sem esperar outra releitura.
    Crm::Entrega::Marca.revalidada!(conversa, ate: 0, razao: nil)
    conversa.save!
    online(ana, bruno)
    Crm::Ai::HandoffDrainJob.new.send(:drain_conversation, conversa.reload)

    expect(conversa.reload.assignee_id).to eq(bruno.id)
  end
end
