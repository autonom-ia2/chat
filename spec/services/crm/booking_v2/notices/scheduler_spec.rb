require 'rails_helper'

# Agenda de avisos (#1192): J5-A1 (três avisos por padrão), J5-A8 (três jogos prontos, sem digitar horário), aviso
# no passado não nasce, remarcar reprograma, cancelar e parar pulam os pendentes.
RSpec.describe Crm::BookingV2::Notices::Scheduler do
  let(:account) { create(:account) }
  let(:world) { build_booking_world(account: account) }
  let(:inbox) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false).inbox }
  let(:starts_at) { Time.zone.parse('2026-10-20T13:00:00Z') }
  let(:meeting) { create_internal_meeting(world: world, starts_at: starts_at, metadata: { 'booking_profile_id' => world.profile.id }) }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true') do
      travel_to(Time.zone.parse('2026-10-12T14:00:00Z')) { example.run }
    end
  end

  before do
    account.enable_features('crm_booking_v2')
    account.save!
    world.profile.update!(notice_inbox: inbox)
  end

  def schedule_of(target = meeting)
    target.notices.reload.order(:due_at).map { |notice| [notice.kind, notice.due_at, notice.status] }
  end

  it 'cria por padrão os três avisos: ao marcar (agora), 1 dia antes e 1 hora antes (J5-A1)' do
    described_class.new(meeting).schedule!

    expect(schedule_of).to eq(
      [['booked', Time.current, 'pending'], ['day_before', starts_at - 1.day, 'pending'], ['hour_before', starts_at - 1.hour, 'pending']]
    )
  end

  it 'segue o jogo escolhido pelo admin (J5-A8)' do
    { 'light' => %w[booked hour_before], 'minimal' => %w[booked] }.each do |preset, kinds|
      world.profile.update!(notice_preset: preset)
      other = create_internal_meeting(world: world, starts_at: starts_at + 2.days, metadata: { 'booking_profile_id' => world.profile.id })

      described_class.new(other).schedule!

      expect(other.notices.order(:due_at).pluck(:kind)).to eq(kinds), preset
    end
  end

  it 'não cria lembrete cujo horário já passou' do
    soon = create_internal_meeting(world: world, starts_at: 3.hours.from_now, metadata: { 'booking_profile_id' => world.profile.id })

    described_class.new(soon).schedule!

    expect(soon.notices.pluck(:kind)).to contain_exactly('booked', 'hour_before')
  end

  it 'não cria lembrete a menos de 30 minutos de outro aviso da reunião (marcar 1h10 antes não manda "1 hora antes" 10 min depois)' do
    soon = create_internal_meeting(world: world, starts_at: 70.minutes.from_now, metadata: { 'booking_profile_id' => world.profile.id })
    tomorrow = create_internal_meeting(world: world, starts_at: 1.day.from_now + 20.minutes, metadata: { 'booking_profile_id' => world.profile.id })

    [soon, tomorrow].each { |target| described_class.new(target).schedule! }

    expect(soon.notices.pluck(:kind)).to eq(%w[booked])
    expect(tomorrow.notices.order(:due_at).pluck(:kind)).to eq(%w[booked hour_before])
    expect(described_class::MIN_GAP).to eq(30.minutes)
  end

  it 'repetir não duplica, guarda a conversa do convite e não faz nada sem caixa de avisos' do
    conversation = create(:conversation, account: account, inbox: inbox, contact: world.contact)
    invite = create_booking_invite(world: world, conversation: conversation)

    2.times { described_class.new(meeting).schedule!(invite: invite) }

    expect(meeting.notices.count).to eq(3)
    expect(meeting.reload.conversation_id).to eq(conversation.id)

    world.profile.update!(notice_inbox: nil)
    other = create_internal_meeting(world: world, starts_at: starts_at + 1.day, metadata: { 'booking_profile_id' => world.profile.id })
    described_class.new(other).schedule!
    expect(other.notices.count).to eq(0)
  end

  it 'reunião sem página nova (ex.: marcada pelo painel) não ganha aviso' do
    manual = create_internal_meeting(world: world, starts_at: starts_at + 1.day)

    described_class.new(manual).schedule!

    expect(manual.notices.count).to eq(0)
  end

  it 'contato que já parou os avisos ganha a reunião nova com avisos parados' do
    Crm::BookingNoticeStop.create!(account: account, contact: world.contact)

    described_class.new(meeting).schedule!

    expect(meeting.reload.reminders_stopped_at).to eq(Time.current)
  end

  describe '#reschedule!' do
    it 'manda o aviso de remarcado agora, leva os lembretes para o novo horário e substitui o "marcado" que não saiu' do
      described_class.new(meeting).schedule!
      meeting.notices.find_by(kind: 'day_before').update!(status: :sent, sent_at: Time.current, message_id: 99)
      new_start = starts_at + 2.days
      meeting.update!(starts_at: new_start, ends_at: new_start + 30.minutes)

      described_class.new(meeting).reschedule!

      rows = meeting.notices.reload.index_by(&:kind)
      expect(rows['booked']).to have_attributes(status: 'skipped', skip_reason: 'replaced')
      expect(rows['rescheduled']).to have_attributes(status: 'pending', due_at: Time.current)
      expect(rows['day_before']).to have_attributes(status: 'pending', due_at: new_start - 1.day, message_id: nil, sent_at: Time.current)
      expect(rows['hour_before']).to have_attributes(status: 'pending', due_at: new_start - 1.hour)
    end

    it 'não mexe no aviso que está saindo agora e pula o lembrete que ficou no passado' do
      described_class.new(meeting).schedule!
      meeting.notices.find_by(kind: 'hour_before').update!(status: :sending)
      new_start = 20.hours.from_now
      meeting.update!(starts_at: new_start, ends_at: new_start + 30.minutes)

      described_class.new(meeting).reschedule!

      rows = meeting.notices.reload.index_by(&:kind)
      expect(rows['hour_before']).to have_attributes(status: 'sending', due_at: starts_at - 1.hour)
      expect(rows['day_before']).to have_attributes(status: 'skipped', skip_reason: 'past_due')
    end
  end

  describe '.meeting_moved!' do
    it 'reunião de página nova: confirmação volta a pendente e os avisos são reprogramados' do
      described_class.new(meeting).schedule!
      moved = starts_at + 1.day
      meeting.update!(confirmation_status: :confirmed, confirmed_at: Time.current, starts_at: moved, ends_at: moved + 30.minutes)

      described_class.meeting_moved!(meeting)

      expect(meeting.reload).to have_attributes(confirmation_status: 'pending', confirmed_at: nil)
      expect(meeting.notices.find_by(kind: 'rescheduled')).to have_attributes(status: 'pending', due_at: Time.current)
      expect(meeting.notices.find_by(kind: 'hour_before').due_at).to eq(starts_at + 1.day - 1.hour)
    end

    it 'reunião sem página nova não muda nada' do
      manual = create_internal_meeting(world: world, starts_at: starts_at + 1.day)
      manual.update!(confirmation_status: :confirmed, confirmed_at: Time.current)

      described_class.meeting_moved!(manual)

      expect(manual.reload.confirmation_status).to eq('confirmed')
      expect(manual.notices).to be_empty
    end
  end

  it '#reschedule! pula com too_close o lembrete que ficaria a menos de 30 minutos do "remarcado"' do
    described_class.new(meeting).schedule!
    new_start = 80.minutes.from_now
    meeting.update!(starts_at: new_start, ends_at: new_start + 30.minutes)

    described_class.new(meeting).reschedule!

    rows = meeting.notices.reload.index_by(&:kind)
    expect(rows['hour_before']).to have_attributes(status: 'skipped', skip_reason: 'too_close')
    expect(rows['day_before']).to have_attributes(status: 'skipped', skip_reason: 'past_due')
    expect(rows['rescheduled']).to have_attributes(status: 'pending', due_at: Time.current)
  end

  it '#skip_pending! pula só os pendentes, com o motivo' do
    described_class.new(meeting).schedule!
    meeting.notices.find_by(kind: 'booked').update!(status: :sent, sent_at: Time.current)

    described_class.new(meeting).skip_pending!('canceled')

    expect(meeting.notices.order(:due_at).pluck(:kind, :status, :skip_reason)).to eq(
      [%w[booked sent] + [nil], %w[day_before skipped canceled], %w[hour_before skipped canceled]]
    )
  end
end
