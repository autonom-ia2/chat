require 'rails_helper'

# Arquivar é um caminho só (pessoa, lote e IA): o card arquivado não deixa sugestão pendente nem lembrete por vencer, e
# a reunião marcada com o cliente fica (cancelar avisaria o cliente).
RSpec.describe Crm::Cards::Archiver do
  let(:account) { create(:account) }
  let(:world) { build_booking_world(account: account) }
  let(:card) { world.card }
  let(:host) { world.host }

  def lembrete(**attrs)
    Crm::FollowUp.create!({ account: account, card: card, created_by: host, title: 'Ligar', due_at: 2.days.from_now,
                            timezone: 'America/Sao_Paulo', status: :pending }.merge(attrs))
  end

  def sugestao
    account.crm_ai_stage_suggestions.create!(card: card, from_stage: card.stage, to_stage: card.stage, confidence: 0.9, model_used: 't')
  end

  def serie
    Crm::FollowUpSeries.create!(account: account, card: card, created_by: host, title: 'Toda segunda', frequency: :weekly,
                                starts_at: 1.day.from_now, timezone: 'America/Sao_Paulo', weekdays: [1])
  end

  it 'arquiva e expira as sugestões pendentes' do
    pendente = sugestao

    expect(described_class.new(card: card, actor: host).perform).to be(true)

    expect(card.reload).to be_archived
    expect(pendente.reload).to be_expired
  end

  it 'cancela os lembretes por vencer e encerra o que repete' do
    tarefa = lembrete(follow_up_type: :task)
    atrasado = lembrete(status: :overdue, due_at: 1.day.ago)
    feito = lembrete(status: :done)
    repete = serie

    described_class.new(card: card, actor: host).perform

    expect([tarefa, atrasado].map { |item| item.reload.status }).to eq(%w[canceled canceled])
    expect(tarefa.metadata['canceled_reason']).to eq('card_archived')
    expect(feito.reload).to be_done
    expect(repete.reload).to be_ended
    expect(card.next_follow_up_at).to be_nil
    expect(card.activities.where(event_type: 'archive').last.payload).to include('lembretes_cancelados' => 2)
  end

  it 'mantém a reunião marcada e o lembrete dela, e registra quais ficaram' do
    reuniao = create_internal_meeting(world: world, starts_at: 3.days.from_now)
    do_encontro = lembrete(follow_up_type: :meeting)
    reuniao.update!(reminder: do_encontro)

    described_class.new(card: card, actor: host).perform

    expect(reuniao.reload).to be_scheduled
    expect(do_encontro.reload).to be_pending
    expect(card.activities.where(event_type: 'archive').last.payload).to include('reunioes_mantidas' => [reuniao.id])
  end

  it 'card já arquivado: nada muda e nada é registrado de novo' do
    described_class.new(card: card, actor: host).perform

    expect(described_class.new(card: card, actor: host).perform).to be(false)
    expect(card.activities.where(event_type: 'archive').count).to eq(1)
  end

  it 'encerra a cadência do follow-up de IA, que ficava active: true com as tarefas canceladas' do
    card.update!(metadata: card.metadata.to_h.merge('ai' => { 'auto_followup_state' => { 'active' => true, 'touch' => 1 } }))
    tarefa = lembrete(metadata: { 'source' => 'ai_followup' })

    described_class.new(card: card, actor: host).perform

    expect(tarefa.reload).to be_canceled
    expect(card.reload.metadata.dig('ai', 'auto_followup_state'))
      .to include('active' => false, 'spent' => true, 'stopped_reason' => 'card_archived', 'touch' => 1)
  end
end
