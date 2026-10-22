require 'rails_helper'

# Arquivar funil (#2095, Parte B, revisão): a regra do último funil ativo da Parte A vale no DELETE, o destino é conferido
# sob a trava, os retornos dos cards que ficam param e o card de dono que saiu da conta não trava o arquivamento.
RSpec.describe Crm::Pipelines::Archiver do
  let(:account) { create(:account) }
  let(:world) { build_booking_world(account: account) }
  let(:host) { world.host }
  let(:pipeline) { world.pipeline }
  let(:card) { world.card }
  let(:other_pipeline_and_stage) { create_crm_pipeline(account: account, user: host, name: 'Vendas') }
  let(:target_stage) { other_pipeline_and_stage.last }

  def lembrete(**attrs)
    Crm::FollowUp.create!({ account: account, card: card, created_by: host, title: 'Ligar', due_at: 2.days.from_now,
                            timezone: 'America/Sao_Paulo', status: :pending }.merge(attrs))
  end

  def serie
    Crm::FollowUpSeries.create!(account: account, card: card, created_by: host, title: 'Toda segunda', frequency: :weekly,
                                starts_at: 1.day.from_now, timezone: 'America/Sao_Paulo', weekdays: [1])
  end

  # Quem saiu da conta sem o Agents::DestroyJob ter rodado (os cards de antes da correção).
  def dono_sai_da_conta!(user)
    AccountUser.where(account: account, user: user).delete_all
  end

  before { other_pipeline_and_stage }

  it 'recusa arquivar o último funil ativo, com o motivo da Parte A, e não muda nada' do
    other_pipeline_and_stage.first.archived!

    expect { described_class.new(pipeline: pipeline, actor: host).perform }
      .to raise_error(described_class::Blocked) { |error| expect(error.motivo).to eq('last_active') }
    expect(pipeline.reload).to be_active
  end

  it 'recusa o destino que foi arquivado depois da escolha, e os cards não ficam presos de novo' do
    target_stage.pipeline.archived!
    other = create_crm_pipeline(account: account, user: host, name: 'Terceiro').first

    expect { described_class.new(pipeline: pipeline, actor: host, target_stage: target_stage).perform }
      .to raise_error(described_class::InvalidTarget)
    expect(pipeline.reload).to be_active
    expect(other.reload).to be_active
    expect(card.reload.pipeline_id).to eq(pipeline.id)
  end

  def reuniao_com_lembrete
    reuniao = create_internal_meeting(world: world, starts_at: 3.days.from_now)
    do_encontro = lembrete(follow_up_type: :meeting)
    reuniao.update!(reminder: do_encontro)
    [reuniao, do_encontro]
  end

  it 'a prévia conta os retornos que param e as reuniões que continuam' do
    lembrete
    serie
    reuniao_com_lembrete
    lembrete(status: :done)

    expect(Crm::Pipelines::RetornosDosGuardados.new(pipeline).contagem)
      .to eq(follow_ups_count: 1, follow_up_series_count: 1, upcoming_meetings_count: 1)
  end

  it 'ao guardar junto, para os retornos dos cards abertos e mantém a reunião com o lembrete dela' do
    tarefa = lembrete
    repete = serie
    reuniao, do_encontro = reuniao_com_lembrete

    result = described_class.new(pipeline: pipeline, actor: host).perform

    expect(result.stopped_follow_ups).to eq(1)
    expect(pipeline.reload).to be_archived
    expect(tarefa.reload).to be_canceled
    expect(tarefa.metadata['canceled_reason']).to eq('pipeline_archived')
    expect(repete.reload).to be_ended
    expect([reuniao.reload.status, do_encontro.reload.status]).to eq(%w[scheduled pending])
    expect(card.reload.next_follow_up_at).to eq(do_encontro.due_at)
  end

  it 'ao mover, os retornos seguem com o card no funil novo' do
    tarefa = lembrete

    result = described_class.new(pipeline: pipeline, actor: host, target_stage: target_stage).perform

    expect(result.moved.map(&:id)).to eq([card.id])
    expect(result.stopped_follow_ups).to eq(0)
    expect(tarefa.reload).to be_pending
  end

  it 'card de dono que saiu da conta vai sem dono, e o histórico diz quem era' do
    dono_sai_da_conta!(host)

    described_class.new(pipeline: pipeline, actor: nil, target_stage: target_stage).perform

    card.reload
    expect([card.pipeline_id, card.owner_id]).to eq([target_stage.pipeline_id, nil])
    expect(card.activities.find_by!(event_type: 'move').payload).to include('dono_que_saiu_id' => host.id)
  end
end
