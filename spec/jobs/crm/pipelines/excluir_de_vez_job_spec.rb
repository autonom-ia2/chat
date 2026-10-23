require 'rails_helper'

# Excluir de vez um funil com cards (#2096): o job confere de novo e, quando algo barra, não apaga nada e deixa o
# desfecho na Auditoria da conta (motivo em código, só ids).
RSpec.describe Crm::Pipelines::ExcluirDeVezJob do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:pipeline) { pipeline_and_stage.first }
  let(:destino) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let(:contact) { account.contacts.create!(name: 'Cliente', phone_number: '+5511999990004') }
  let!(:card) { account.crm_cards.create!(pipeline: pipeline, stage: pipeline_and_stage.last, contact: contact, title: 'Pedido') }

  before { pipeline.archived! }

  def falha
    Audited.audit_class.where(auditable: account, action: Crm::ExclusaoDefinitiva::FALHOU).sole.audited_changes
  end

  def nada_apagado?
    [Crm::Pipeline.exists?(pipeline.id), card.reload.pipeline_id] == [true, pipeline.id]
  end

  it 'move e apaga o funil' do
    described_class.perform_now(pipeline.id, admin.id, 'move', destino.last.id)

    expect(Crm::Pipeline.exists?(pipeline.id)).to be(false)
    expect(card.reload.pipeline_id).to eq(destino.first.id)
  end

  it 'o segundo job do mesmo pedido (dois cliques) sai sem fazer nada nem registrar de novo' do
    2.times { described_class.perform_now(pipeline.id, admin.id, 'delete') }

    expect(Crm::Card.exists?(card.id)).to be(false)
    expect(Audited.audit_class.where(auditable: account, action: Crm::ExclusaoDefinitiva::ACAO).count).to eq(1)
    expect(Audited.audit_class.where(auditable: account, action: Crm::ExclusaoDefinitiva::FALHOU)).to be_empty
  end

  # Sem nova tentativa: uma tentativa horas depois apagaria o funil que a Auditoria já disse que ficou.
  it 'erro inesperado: nada é apagado, o motivo fica na Auditoria, vai ao monitoramento e o job não tenta de novo' do
    allow(Crm::Pipelines::Excluidor).to receive(:new).and_raise(NoMethodError, 'falhou')
    tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
    allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)

    expect { described_class.perform_now(pipeline.id, admin.id, 'delete') }.not_to raise_error

    expect(tracker).to have_received(:capture_exception)
    expect(described_class.get_sidekiq_options['retry']).to be(false)

    expect(nada_apagado?).to be(true)
    expect(falha).to eq('alvo' => 'funil', 'motivo' => 'internal_error', 'pipeline_id' => pipeline.id, 'error_class' => 'NoMethodError')
  end

  it 'não faz nada quando o destino foi arquivado enquanto esperava, e registra o motivo' do
    destino.first.archived!

    described_class.perform_now(pipeline.id, admin.id, 'move', destino.last.id)

    expect(nada_apagado?).to be(true)
    expect(falha).to eq('alvo' => 'funil', 'motivo' => 'target_unavailable', 'pipeline_id' => pipeline.id, 'target_stage_id' => destino.last.id)
  end

  it 'não faz nada quando um card não pode ir para o destino, e registra qual' do
    dono = create(:user, account: account, role: :agent)
    card.update!(owner: dono)
    AccountUser.find_by!(account: account, user: dono).destroy!

    described_class.perform_now(pipeline.id, admin.id, 'move', destino.last.id)

    expect(nada_apagado?).to be(true)
    expect(falha).to include('motivo' => 'card_rejected', 'record_type' => 'Crm::Card', 'record_id' => card.id)
  end

  it 'não apaga nada quando a reunião futura não cancela, e registra a reunião' do
    meeting = create_reuniao(account: account, card: card, user: admin, contact: contact, starts_at: 2.days.from_now)
    servico = instance_double(Crm::Meetings::CancelService)
    allow(servico).to receive(:perform).and_raise(Net::OpenTimeout)
    allow(Crm::Meetings::CancelService).to receive(:new).and_return(servico)

    described_class.perform_now(pipeline.id, admin.id, 'delete')

    expect([Crm::Pipeline.exists?(pipeline.id), Crm::Card.exists?(card.id)]).to eq([true, true])
    expect(falha).to eq('alvo' => 'funil', 'motivo' => 'meeting_cancel_failed', 'pipeline_id' => pipeline.id, 'meeting_id' => meeting.id)
  end
end
