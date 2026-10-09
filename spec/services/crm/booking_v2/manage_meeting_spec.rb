require 'rails_helper'

# Página de gestão (#1192): J5-A3 (cancelar ou remarcar libera o horário na hora e avisa o agente; prazo), J5-A6
# (confirmar duas vezes não avisa duas vezes), J5-A7 (parar avisos fica registrado e a reunião continua), RA-19
# (cada ação vira atividade no card).
RSpec.describe Crm::BookingV2::ManageMeeting do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:world) { build_booking_world(account: account) }
  let(:inbox) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false).inbox }
  let(:starts_at) { Time.zone.parse('2026-10-20T13:00:00Z') }
  let(:meeting) { create_internal_meeting(world: world, starts_at: starts_at, metadata: { 'booking_profile_id' => world.profile.id }) }
  let(:invite) { create_booking_invite(world: world, meeting: meeting, scheduled_at: Time.current, channel: 'public') }
  let(:manage) { described_class.new(invite) }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true') do
      travel_to(Time.zone.parse('2026-10-12T14:00:00Z')) { example.run }
    end
  end

  before do
    account.enable_features('crm_booking_v2')
    account.save!
    world.profile.update!(notice_inbox: inbox)
    Crm::BookingV2::Notices::Scheduler.new(meeting).schedule!(invite: invite)
  end

  def free_on(date)
    Crm::BookingV2::Slots.new(profile: world.profile, host: world.host, date: date).perform
  end

  def alerts(event)
    Crm::FollowUp.where(account_id: account.id).where("metadata->>'event' = ?", event)
  end

  def activities(type)
    Crm::Activity.where(card_id: world.card.id, event_type: type)
  end

  # O relógio já está parado no `around`: em vez de andar no tempo, a reunião vem para perto de agora.
  def starts_in(duration)
    meeting.update_columns(starts_at: duration.from_now, ends_at: duration.from_now + 30.minutes) # rubocop:disable Rails/SkipsModelValidations
  end

  def expect_refusal(code, &)
    expect(&).to raise_error(Crm::BookingV2::ManageError, code)
  end

  describe '#confirm! (J5-A6)' do
    it 'marca como confirmada e avisa o agente uma vez, mesmo tocando duas vezes' do
      2.times { described_class.new(invite).confirm! }

      expect(meeting.reload).to have_attributes(confirmation_status: 'confirmed', confirmed_at: Time.current, status: 'scheduled')
      expect(alerts('confirmed').count).to eq(1)
      expect(alerts('confirmed').sole).to have_attributes(assignee_id: world.host.id, title: 'Marcos Lima confirmou o horário de 20/10 às 10:00')
      expect(activities('booking_client_confirmed').count).to eq(1)
    end

    it 'recusa reunião cancelada' do
      meeting.update!(status: :canceled)

      expect_refusal('not_changeable') { manage.confirm! }
      expect(meeting.reload.confirmation_status).to eq('pending')
    end
  end

  describe '#cancel! (J5-A3)' do
    it 'cancela, libera o horário na hora, pula os avisos pendentes e avisa o agente' do
      expect(free_on('2026-10-20')).not_to include('2026-10-20T10:00:00-03:00')

      manage.cancel!

      expect(meeting.reload.status).to eq('canceled')
      expect(free_on('2026-10-20')).to include('2026-10-20T10:00:00-03:00')
      expect(meeting.notices.pluck(:status, :skip_reason).uniq).to eq([%w[skipped canceled]])
      expect(alerts('canceled').count).to eq(1)
      expect(activities('booking_client_canceled').sole.payload).to include('meeting_id' => meeting.id, 'by' => 'client')
    end

    it 'recusa depois do prazo (2 h antes, por padrão) e não mexe na reunião' do
      starts_in(119.minutes)

      expect_refusal('too_late') { manage.cancel! }
      expect(meeting.reload.status).to eq('scheduled')
      expect(alerts('canceled')).to be_empty
    end

    it 'segue o prazo da página' do
      world.profile.update!(cancel_until_minutes: 0)
      starts_in(1.minute)

      manage.cancel!

      expect(meeting.reload.status).to eq('canceled')
    end

    it 'recusa reunião já cancelada' do
      manage.cancel!

      expect_refusal('not_changeable') { described_class.new(invite.reload).cancel! }
      expect(alerts('canceled').count).to eq(1)
    end
  end

  describe '#reschedule! (J5-A3)' do
    it 'move a MESMA reunião, libera o horário antigo, toma o novo, reprograma avisos e avisa o agente' do
      meeting.update!(confirmation_status: :confirmed, confirmed_at: Time.current)

      expect { manage.reschedule!(starts_at: '2026-10-21T11:00:00-03:00') }.not_to change(Crm::Meeting, :count)

      expect(meeting.reload).to have_attributes(starts_at: Time.zone.parse('2026-10-21T14:00:00Z'), ends_at: Time.zone.parse('2026-10-21T14:30:00Z'),
                                                status: 'scheduled', confirmation_status: 'pending', confirmed_at: nil)
      expect([free_on('2026-10-20').include?('2026-10-20T10:00:00-03:00'), free_on('2026-10-21').include?('2026-10-21T11:00:00-03:00')])
        .to eq([true, false])
      expect(meeting.notices.where(kind: %w[rescheduled day_before]).order(:kind).pluck(:kind, :status, :due_at)).to eq(
        [['day_before', 'pending', Time.zone.parse('2026-10-20T14:00:00Z')], ['rescheduled', 'pending', Time.current]]
      )
      expect(alerts('rescheduled').sole.title).to eq('Marcos Lima mudou o horário para 21/10 às 11:00')
      expect(activities('booking_client_rescheduled').sole.payload).to include('from' => starts_at.iso8601, 'by' => 'client')
    end

    it 'aceita um horário que encosta no antigo (a própria reunião não ocupa)' do
      manage.reschedule!(starts_at: '2026-10-20T10:30:00-03:00')

      expect(meeting.reload.starts_at).to eq(Time.zone.parse('2026-10-20T13:30:00Z'))
    end

    it 'recusa horário ocupado por outra reunião do responsável, sem mexer na reunião' do
      create_internal_meeting(world: world, starts_at: Time.zone.parse('2026-10-21T14:00:00Z'))

      expect_refusal('slot_unavailable') { manage.reschedule!(starts_at: '2026-10-21T11:00:00-03:00') }
      expect(meeting.reload.starts_at).to eq(starts_at)
      expect(alerts('rescheduled')).to be_empty
    end

    it 'recusa fora do horário de trabalho, data inválida e duração que a página não oferece' do
      expect_refusal('slot_unavailable') { manage.reschedule!(starts_at: '2026-10-21T20:00:00-03:00') }
      expect_refusal('slot_unavailable') { manage.reschedule!(starts_at: 'amanhã') }
      expect_refusal('slot_unavailable') { manage.reschedule!(starts_at: '2026-10-21T11:00:00-03:00', duration: 45) }
      expect(meeting.reload.starts_at).to eq(starts_at)
    end

    it 'recusa depois do prazo e reunião cancelada' do
      starts_in(1.hour)
      expect_refusal('too_late') { manage.reschedule!(starts_at: '2026-10-21T11:00:00-03:00') }

      meeting.update!(status: :canceled)
      expect_refusal('not_changeable') { described_class.new(invite.reload).reschedule!(starts_at: '2026-10-21T11:00:00-03:00') }
    end
  end

  describe '#stop_notices! (J5-A7)' do
    it 'registra a parada do contato, para os avisos desta e das outras reuniões abertas dele e a reunião continua' do
      other = create_internal_meeting(world: world, starts_at: starts_at + 2.days, metadata: { 'booking_profile_id' => world.profile.id })
      Crm::BookingV2::Notices::Scheduler.new(other).schedule!

      2.times { described_class.new(invite).stop_notices! }

      expect(Crm::BookingNoticeStop.where(account_id: account.id, contact_id: world.contact.id).sole.reason).to eq('client_link')
      expect([meeting.reload, other.reload].map(&:reminders_stopped_at)).to eq([Time.current, Time.current])
      expect(Crm::MeetingNotice.where(meeting_id: [meeting.id, other.id]).pluck(:status, :skip_reason).uniq).to eq([%w[skipped stopped]])
      expect(meeting.status).to eq('scheduled')
      expect(activities('booking_notices_stopped').count).to eq(1)
      expect(Crm::FollowUp.where(account_id: account.id).where("metadata->>'source' = ?", 'booking_agent_alert')).to be_empty
    end
  end
end
