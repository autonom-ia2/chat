require 'rails_helper'

# #1975: o pedido de pessoa fica no card na hora da decisão (não só na entrega), com o motivo; e o motivo vai na marca
# da espera, para a fila entregar com ele.
RSpec.describe Crm::Ai::HandoffExecutor do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:inbox) { create_crm_inbox(account: account, members: [agent]) }
  let(:conversation) { create_crm_conversation(account: account, inbox: inbox, contact: contact) }
  let(:card) do
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    stage.update!(metadata: { 'ai_handoff' => { 'enabled' => true, 'handoff_mode' => 'r2_direct' } })
    account.crm_cards.create!(pipeline: pipeline, stage: stage, inbox: inbox, contact: contact, primary_conversation: conversation,
                              title: 'Pedido')
  end
  let(:handoff) { { intent: 'transferir', reason: 'cliente pediu explicação da cotação e o robô não soube' } }

  around do |example|
    with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true') { example.run }
  end

  before do
    allow(Rails.configuration.dispatcher).to receive(:dispatch)
    allow(OnlineStatusTracker).to receive(:get_available_users).with(account.id).and_return({})
  end

  def pedidos
    Crm::Activity.where(card_id: card.id, event_type: 'ai_handoff_requested')
  end

  it 'na decisão: atividade com o motivo e o id da avaliação; segurando, a marca guarda o motivo', :aggregate_failures do
    described_class.new(card: card, handoff: handoff, avaliacao: 'resp_123').perform

    expect(pedidos.sole.payload).to include('reason' => handoff[:reason], 'trigger' => 'message', 'evaluation_id' => 'resp_123')
    expect(Crm::Entrega::Marca.dados(conversation.reload)).to include('motivo' => 'ia_crm', 'razao' => handoff[:reason])
  end

  it 'a avaliação seguinte, com a conversa já esperando pelo mesmo pedido, não repete a atividade' do
    described_class.new(card: card, handoff: handoff).perform
    described_class.new(card: card.reload, handoff: handoff).perform

    expect(pedidos.count).to eq(1)
  end

  it 'a fila do caminho antigo (drain) e o pedido barrado não registram pedido', :aggregate_failures do
    described_class.new(card: card, handoff: handoff, trigger: 'drain').perform
    expect(pedidos).to be_empty

    described_class.new(card: card, handoff: { intent: 'continuar', reason: '' }).perform
    expect(pedidos).to be_empty
  end
end
