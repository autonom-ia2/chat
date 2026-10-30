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

  # #2145: em lotes, o que a transação final recusaria é recusado antes de o primeiro card sair.
  it 'mover em lotes: a regra do único principal recusa antes de mover qualquer card' do
    stub_const("#{described_class}::LOTE", 1)
    pipeline.update!(is_default: true)
    target_stage.pipeline.update!(is_default: false)
    account.crm_cards.create!(pipeline: pipeline, stage: card.stage, title: 'Segundo')

    expect { described_class.new(pipeline: pipeline, actor: host, target_stage: target_stage).perform }
      .to raise_error(described_class::Blocked) { |error| expect(error.motivo).to eq('only_default') }
    expect(pipeline.reload).to be_active
    expect(card.reload.pipeline_id).to eq(pipeline.id)
  end

  # Outro pedido arquivou este funil entre dois lotes ("Guardar junto"): os cards que ele guardou não vão para o destino.
  it 'mover em lotes: funil arquivado por outro pedido no meio recusa (CHANGED) e conta os já levados' do
    stub_const("#{described_class}::LOTE", 1)
    segundo = account.crm_cards.create!(pipeline: pipeline, stage: card.stage, title: 'Segundo')
    account.crm_cards.create!(pipeline: pipeline, stage: card.stage, title: 'Terceiro')
    allow(Crm::Activity).to receive(:insert_all!).and_wrap_original do |original, *args|
      original.call(*args).tap { Crm::Pipeline.where(id: pipeline.id).update_all(status: Crm::Pipeline.statuses[:archived]) } # rubocop:disable Rails/SkipsModelValidations
    end
    arquivador = described_class.new(pipeline: pipeline, actor: host, target_stage: target_stage, new_default: target_stage.pipeline)

    expect { arquivador.perform }.to raise_error(described_class::InvalidTarget, described_class::CHANGED)
    expect(arquivador.moved_before_failure).to eq(1)
    expect(card.reload.pipeline_id).to eq(target_stage.pipeline_id)
    expect(segundo.reload.pipeline_id).to eq(pipeline.id)
  end

  # #2145, opção 1 do Rodrigo: o cliente que já tinha card aberto no destino recebe o card movido mesmo assim (R1 do
  # multifunil), e o resultado o lista para o resumo. Também em lotes; cliente sem card no destino não entra.
  it 'cliente que já tinha card aberto no destino: move mesmo assim e lista o cliente, uma vez' do
    stub_const("#{described_class}::LOTE", 1)
    ana = account.contacts.create!(name: 'Ana')
    bia = account.contacts.create!(name: 'Bia')
    ja_no_destino = account.crm_cards.create!(pipeline: target_stage.pipeline, stage: target_stage, title: 'Outro assunto', contact: ana)
    da_ana = [1, 2].map { |i| account.crm_cards.create!(pipeline: pipeline, stage: card.stage, title: "Ana #{i}", contact: ana) }
    da_bia = account.crm_cards.create!(pipeline: pipeline, stage: card.stage, title: 'Bia', contact: bia)

    result = described_class.new(pipeline: pipeline, actor: host, target_stage: target_stage).perform

    expect([*da_ana, da_bia].map { |movido| movido.reload.pipeline_id }.uniq).to eq([target_stage.pipeline_id])
    expect(ja_no_destino.reload).to have_attributes(status: 'open', pipeline_id: target_stage.pipeline_id)
    expect(result.clientes_com_dois_abertos).to eq([{ contact_id: ana.id, name: 'Ana', card_id: da_ana.first.id }])
  end

  it 'resumo que falha depois de arquivar não vira erro: arquiva e devolve a lista vazia' do
    arquivador = described_class.new(pipeline: pipeline, actor: host, target_stage: target_stage)
    allow(arquivador).to receive(:clientes_com_dois_abertos).and_raise(ActiveRecord::StatementInvalid, 'tempo esgotado')

    result = arquivador.perform

    expect(pipeline.reload).to be_archived
    expect(result.clientes_com_dois_abertos).to eq([])
    expect(arquivador.moved_before_failure).to eq(0)
  end

  # Com o novo principal, os lotes saem e a transação final promove o novo principal e arquiva.
  it 'mover em lotes: leva todos os cards abertos e devolve todos em moved' do
    stub_const("#{described_class}::LOTE", 1)
    segundo = account.crm_cards.create!(pipeline: pipeline, stage: card.stage, title: 'Segundo')
    pipeline.update!(is_default: true)

    result = described_class.new(pipeline: pipeline, actor: host, target_stage: target_stage, new_default: target_stage.pipeline).perform

    expect(result.moved.map(&:id)).to eq([card.id, segundo.id])
    expect(pipeline.reload).to have_attributes(status: 'archived', is_default: false)
    expect(target_stage.pipeline.reload).to be_is_default
    expect(Crm::Activity.where(card_id: [card.id, segundo.id], event_type: 'move').count).to eq(2)
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

    result = described_class.new(pipeline: pipeline, actor: host, stop_follow_ups: true).perform

    expect(result.stopped_follow_ups).to eq(1)
    expect(pipeline.reload).to be_archived
    expect(tarefa.reload).to be_canceled
    expect(tarefa.metadata['canceled_reason']).to eq('pipeline_archived')
    expect(repete.reload).to be_ended
    expect([reuniao.reload.status, do_encontro.reload.status]).to eq(%w[scheduled pending])
    expect(card.reload.next_follow_up_at).to eq(do_encontro.due_at)
  end

  it 'sem pedir para parar (a janela antiga, flag desligada), arquiva como antes e os retornos seguem' do
    tarefa = lembrete
    repete = serie

    result = described_class.new(pipeline: pipeline, actor: host).perform

    expect(result.stopped_follow_ups).to eq(0)
    expect(pipeline.reload).to be_archived
    expect(tarefa.reload).to be_pending
    expect(repete.reload).not_to be_ended
  end

  it 'ao mover, os retornos seguem com o card no funil novo' do
    tarefa = lembrete

    result = described_class.new(pipeline: pipeline, actor: host, target_stage: target_stage).perform

    expect(result.moved.map(&:id)).to eq([card.id])
    expect(result.stopped_follow_ups).to eq(0)
    expect(tarefa.reload).to be_pending
  end

  describe 'caixas e funil principal (decisão 7)' do
    let(:target_pipeline) { other_pipeline_and_stage.first }
    let(:inbox) { create_crm_inbox(account: account, name: 'Caixa A') }
    let(:other_inbox) { create_crm_inbox(account: account, name: 'Caixa B') }

    def link(pipeline, inbox, auto:)
      account.crm_pipeline_inboxes.create!(pipeline: pipeline, inbox: inbox, auto_create_card: auto)
    end

    it 'move a ligação que o destino não tem, mescla a que ele tem e leva o funil padrão da caixa' do
      moved = link(pipeline, inbox, auto: true)
      link(pipeline, other_inbox, auto: true)
      kept = link(target_pipeline, other_inbox, auto: false)
      setting = account.crm_inbox_settings.create!(inbox: inbox, crm_enabled: true, default_pipeline: pipeline)

      result = described_class.new(pipeline: pipeline, actor: host, inboxes_target: target_pipeline).perform

      expect(result.moved_inboxes).to eq([{ id: inbox.id, name: 'Caixa A' }, { id: other_inbox.id, name: 'Caixa B' }])
      expect(result.inboxes_target_pipeline_id).to eq(target_pipeline.id)
      expect(moved.reload.pipeline_id).to eq(target_pipeline.id)
      expect(account.crm_pipeline_inboxes.where(inbox: other_inbox).pluck(:id, :auto_create_card)).to eq([[kept.id, true]])
      expect([setting.reload.default_pipeline_id, setting.default_stage_id]).to eq([target_pipeline.id, target_stage.id])
    end

    it 'destino das caixas arquivado depois da escolha: recusa e nada muda' do
      moved = link(pipeline, inbox, auto: true)
      create_crm_pipeline(account: account, user: host, name: 'Terceiro')
      target_pipeline.archived!

      expect { described_class.new(pipeline: pipeline, actor: host, inboxes_target: target_pipeline).perform }
        .to raise_error(described_class::InvalidTarget, described_class::INVALID_INBOXES_TARGET)
      expect([pipeline.reload.status, moved.reload.pipeline_id]).to eq(['active', pipeline.id])
    end

    it 'o novo principal vale antes da regra do único principal, e este deixa de ser o principal' do
      pipeline.update!(is_default: true)

      described_class.new(pipeline: pipeline, actor: host, new_default: target_pipeline).perform

      expect([pipeline.reload.status, pipeline.is_default, target_pipeline.reload.is_default]).to eq(['archived', false, true])
    end

    it 'novo principal inválido: recusa e nada muda' do
      pipeline.update!(is_default: true)
      target_pipeline.archived!
      create_crm_pipeline(account: account, user: host, name: 'Terceiro')

      expect { described_class.new(pipeline: pipeline, actor: host, new_default: target_pipeline).perform }
        .to raise_error(described_class::InvalidTarget, described_class::INVALID_DEFAULT)
      expect([pipeline.reload.status, pipeline.is_default]).to eq(['active', true])
    end
  end

  it 'card de dono que saiu da conta vai sem dono, e o histórico diz quem era' do
    dono_sai_da_conta!(host)

    described_class.new(pipeline: pipeline, actor: nil, target_stage: target_stage).perform

    card.reload
    expect([card.pipeline_id, card.owner_id]).to eq([target_stage.pipeline_id, nil])
    expect(card.activities.find_by!(event_type: 'move').payload).to include('dono_que_saiu_id' => host.id)
  end
end
