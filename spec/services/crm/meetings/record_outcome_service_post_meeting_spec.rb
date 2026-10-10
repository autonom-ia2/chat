require 'rails_helper'

# Depois de "Aconteceu" (#1193, J4-A7) e o resultado da reunião (J4-A3): o serviço de resultado existente grava
# compareceu/faltou e a atividade no card; numa reunião de página de agendamento com etapa configurada, `ask` devolve
# a pergunta sem mover e `auto` move o card (atividade `move` + automações da etapa).
RSpec.describe Crm::Meetings::RecordOutcomeService do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:world) { build_booking_world(account: account) }
  let(:proposal) { create_crm_stage(account: account, pipeline: world.pipeline, name: 'Proposta') }
  let(:closer) { create(:user, account: account, role: :agent, name: 'Bruno') }
  let(:meeting) do
    create_internal_meeting(world: world, starts_at: 2.hours.ago, metadata: { 'booking_profile_id' => world.profile.id })
  end

  def record(outcome, notes: nil)
    service = described_class.new(meeting: meeting, outcome: outcome, notes: notes, actor: closer)
    service.perform
    service
  end

  describe 'outcome (J4-A3)' do
    it 'records held and no-show on an internal meeting without calendar mailbox and logs it on the card' do
      expect(meeting.inbox_id).to be_nil

      record('no_show')

      expect(meeting.reload).to have_attributes(outcome: 'no_show', status: 'scheduled')
      expect(meeting.outcome_recorded_at).to be_present
      activity = world.card.activities.find_by(event_type: 'meeting_outcome_recorded')
      expect(activity.payload).to include('meeting_id' => meeting.id, 'outcome' => 'no_show')
    end

    it 'refuses a meeting that has not finished yet' do
      meeting.update!(starts_at: 10.minutes.ago, ends_at: 20.minutes.from_now)

      expect { record('held') }.to raise_error(ArgumentError, 'meeting_not_finished')
      expect(meeting.reload.outcome).to be_nil
    end
  end

  describe 'post_meeting (J4-A7)' do
    it 'asks (without moving) when the page is in ask mode' do
      world.profile.update!(post_meeting_mode: 'ask', post_meeting_stage: proposal)

      service = record('held')

      expect(service.post_meeting).to eq(mode: 'ask', moved: false, stage: { id: proposal.id, name: 'Proposta', pipeline_id: world.pipeline.id })
      expect(world.card.reload.stage_id).to eq(world.stage.id)
      expect(world.card.activities.where(event_type: 'move')).to be_empty
    end

    it 'moves the card by itself in auto mode and logs the move by who recorded the outcome' do
      world.profile.update!(post_meeting_mode: 'auto', post_meeting_stage: proposal)

      service = record('held')

      expect(service.post_meeting).to include(mode: 'auto', moved: true)
      expect(world.card.reload.stage_id).to eq(proposal.id)
      move = world.card.activities.find_by(event_type: 'move')
      expect(move).to have_attributes(actor_id: closer.id, actor_type: 'user')
      expect(move.payload).to include('from_stage_id' => world.stage.id, 'to_stage_id' => proposal.id)
    end

    it 'moves across pipelines when the admin picked a stage of another active pipeline' do
      other_pipeline, other_stage = create_crm_pipeline(account: account, user: world.host, name: 'Pós-venda')
      world.profile.update!(post_meeting_mode: 'auto', post_meeting_stage: other_stage)

      record('held')

      expect(world.card.reload).to have_attributes(pipeline_id: other_pipeline.id, stage_id: other_stage.id)
    end

    it 'offers nothing for no-show, without a stage, outside a booking page, when already there or when the card is closed' do
      world.profile.update!(post_meeting_mode: 'auto', post_meeting_stage: proposal)
      expect(record('no_show').post_meeting).to be_nil

      meeting.update!(outcome: nil)
      world.profile.update!(post_meeting_stage: nil)
      expect(record('held').post_meeting).to be_nil

      meeting.update!(outcome: nil, metadata: {})
      world.profile.update!(post_meeting_stage: proposal)
      expect(record('held').post_meeting).to be_nil

      meeting.update!(outcome: nil, metadata: { 'booking_profile_id' => world.profile.id })
      world.card.update!(stage: proposal)
      expect(record('held').post_meeting).to be_nil

      # Zera a marca do primeiro "Aconteceu" para testar só o card fechado.
      meeting.update!(outcome: nil, metadata: { 'booking_profile_id' => world.profile.id })
      world.card.update!(stage: world.stage, status: :won)
      expect(record('held').post_meeting).to be_nil
      expect(world.card.reload.stage_id).to eq(world.stage.id)
    end

    it 'offers nothing when the stage pipeline was archived after saving' do
      world.profile.update!(post_meeting_mode: 'auto', post_meeting_stage: proposal)
      world.pipeline.update!(status: :archived)

      expect(record('held').post_meeting).to be_nil
    end

    it 'does not take a card of a pipeline outside the page flow to the chosen stage' do
      support_pipeline, support_stage = create_crm_pipeline(account: account, user: world.host, name: 'Suporte')
      world.card.update!(pipeline: support_pipeline, stage: support_stage)
      world.profile.update!(post_meeting_mode: 'auto', post_meeting_stage: proposal)

      expect(record('held').post_meeting).to be_nil
      expect(world.card.reload).to have_attributes(pipeline_id: support_pipeline.id, stage_id: support_stage.id)
      expect(world.card.activities.where(event_type: 'move')).to be_empty
    end

    it 'moves only once per meeting, even after switching to no-show and back to held' do
      world.profile.update!(post_meeting_mode: 'auto', post_meeting_stage: proposal)
      expect(record('held').post_meeting).to include(moved: true)
      expect(meeting.reload.metadata['post_meeting_at']).to be_present

      Crm::Cards::Mover.new(card: world.card.reload, actor: closer, target_stage: world.stage).perform
      record('no_show')

      expect(record('held').post_meeting).to be_nil
      expect(world.card.reload.stage_id).to eq(world.stage.id)
      expect(world.card.activities.where(event_type: 'move').count).to eq(2)
    end

    it 'does not move twice on a double tap: the second request, loaded before the first saved, sees it under the lock' do
      world.profile.update!(post_meeting_mode: 'auto', post_meeting_stage: proposal)
      stale = Crm::Meeting.find(meeting.id)
      expect(stale.card.stage_id).to eq(world.stage.id) # carregado antes do primeiro toque
      record('held')

      second = described_class.new(meeting: stale, outcome: 'held', actor: closer)
      second.perform

      expect(second.post_meeting).to be_nil
      expect(world.card.activities.where(event_type: 'move').count).to eq(1)
    end

    it 'does not ask again when the notes of a held meeting are saved later' do
      world.profile.update!(post_meeting_mode: 'ask', post_meeting_stage: proposal)
      record('held')

      expect(record('held', notes: 'Pediu proposta').post_meeting).to be_nil
      expect(meeting.reload.outcome_notes).to eq('Pediu proposta')
    end
  end
end
