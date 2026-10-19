require 'rails_helper'

# #1876 (F1 de Números): "Atrasados" contava só o lembrete ainda `pending` com o prazo vencido. O DueProcessor roda a
# cada minuto e troca esse lembrete para `overdue`, então o número ficava perto de zero. Atrasado é o que venceu e
# ninguém fez, nos dois estados, separado entre o que é da IA e o que é da equipe.
RSpec.describe Crm::Reports::FollowUps do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: user) }
  let(:card) do
    pipeline, stage = pipeline_and_stage
    account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Lead')
  end

  def follow_up(due_at:, status: :pending, source: nil)
    account.crm_follow_ups.create!(
      card: card, title: 'Retorno', due_at: due_at, timezone: 'UTC', created_by: user, status: status,
      metadata: source ? { 'source' => source } : {}
    )
  end

  def report
    described_class.new(account: account, params: { pipeline_id: pipeline_and_stage.first.id }).perform
  end

  it 'conta o lembrete que o DueProcessor já marcou como atrasado' do
    lembrete = follow_up(due_at: 2.hours.ago)
    allow(Crm::FollowUps::Broadcaster).to receive(:broadcast_due)
    Crm::FollowUps::DueProcessor.new(now: Time.current).perform
    expect(lembrete.reload).to be_overdue

    expect(report).to include(overdue: 1, overdue_by: { ai: 0, human: 1 })
  end

  it 'separa os atrasados da IA dos da equipe e ignora o que foi feito ou cancelado' do
    follow_up(due_at: 3.hours.ago, status: :overdue)
    follow_up(due_at: 1.hour.ago, status: :pending, source: 'ai_followup')
    follow_up(due_at: 2.hours.ago, status: :overdue, source: 'ai_callback')
    follow_up(due_at: 2.hours.ago, status: :overdue, source: 'service_reminder')
    follow_up(due_at: 2.hours.ago, status: :done)
    follow_up(due_at: 2.hours.ago, status: :canceled, source: 'ai_followup')
    follow_up(due_at: 2.hours.from_now)

    expect(report).to include(overdue: 4, overdue_by: { ai: 3, human: 1 }, due_soon: 1)
  end

  # O `group(:status).count` devolve a chave do enum ("pending"), e a leitura procurava pelo número: tudo saía 0.
  it 'conta cada estado em by_status' do
    follow_up(due_at: 3.hours.ago, status: :overdue)
    follow_up(due_at: 2.hours.from_now)
    follow_up(due_at: 2.hours.from_now)
    follow_up(due_at: 2.hours.ago, status: :done)

    expect(report[:by_status]).to eq('pending' => 2, 'done' => 1, 'canceled' => 0, 'overdue' => 1)
  end
end
