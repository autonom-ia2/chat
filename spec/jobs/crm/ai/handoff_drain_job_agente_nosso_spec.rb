require 'rails_helper'

# #1673: a fila da conversa não entrega a uma pessoa a espera que a IA do CRM criou quando, nesse meio tempo, um agente
# nosso passou a atender. A espera que nasceu de um pedido do próprio agente (bot_handoff!) segue para a entrega.
RSpec.describe Crm::Ai::HandoffDrainJob do
  include_context 'with crm responsible agent'

  let(:pessoa) { create(:user, account: account) }

  before do
    inbox.add_members([pessoa.id])
    allow(Rails.configuration.dispatcher).to receive(:dispatch)
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return({ pessoa.id.to_s => 'online' })
  end

  # A trava da rodada é de sessão: sobrevive ao rollback do exemplo (ver handoff_drain_job_fila_spec).
  after { ActiveRecord::Base.connection.execute('SELECT pg_advisory_unlock_all()') }

  def segurar!(motivo)
    Crm::Entrega::Marca.marcar(conversation, modo: Crm::Entrega::Marca::SEGURANDO, motivo: motivo, falha: 'ninguem_online')
    conversation.save!
  end

  it 'com um agente nosso atendendo, tira a espera da IA do CRM e não entrega' do
    segurar!(Crm::Ai::HandoffExecutor::MOTIVO_DA_ENTREGA)

    described_class.perform_now

    expect(conversation.reload).to have_attributes(assignee_id: nil, ai_assignee: porta)
    expect(Crm::Entrega::Marca.presente?(conversation)).to be(false)
  end

  it 'a espera que o próprio agente pediu segue para a entrega' do
    segurar!('robo_pediu')

    described_class.perform_now

    expect(conversation.reload.assignee_id).to eq(pessoa.id)
  end

  it 'sem robô no nome, a espera da IA do CRM segue para a entrega, como hoje' do
    conversation.update!(ai_assignee: nil)
    segurar!(Crm::Ai::HandoffExecutor::MOTIVO_DA_ENTREGA)

    described_class.perform_now

    expect(conversation.reload.assignee_id).to eq(pessoa.id)
  end
end
