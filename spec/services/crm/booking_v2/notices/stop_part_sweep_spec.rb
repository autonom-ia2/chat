require 'rails_helper'

# Conferência da mensagem 2 do aviso com botão (#1562) no cron: a 2 que nunca saiu (job perdido) e a 2 que o provedor
# marcou `failed`. Nos dois casos o aviso fica `sent` com stop_part_failed e o responsável é avisado, sem reenvio.
RSpec.describe Crm::BookingV2::Notices::StopPartSweep do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:world) { build_booking_world(account: account) }
  let(:inbox) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false).inbox
  end
  let(:meeting) do
    create_internal_meeting(world: world, starts_at: Time.zone.parse('2026-10-20T13:00:00Z'),
                            metadata: { 'booking_profile_id' => world.profile.id })
  end
  let!(:conversation) do
    create(:conversation, account: account, inbox: inbox, contact: world.contact).tap do |item|
      create(:message, account: account, inbox: inbox, conversation: item, message_type: :incoming, created_at: 2.hours.ago)
    end
  end
  let(:stop_job) { Crm::BookingV2::NoticeStopPartJob }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true', 'FRONTEND_URL' => 'https://app.example.com') do
      travel_to(Time.zone.parse('2026-10-12T14:00:00Z')) { example.run }
    end
  end

  before do
    account.enable_features('crm_booking_v2')
    account.save!
    world.profile.update!(notice_inbox: inbox)
    create_booking_invite(world: world, meeting: meeting, scheduled_at: Time.current, channel: 'public')
  end

  # Aviso com botão pelo Sender de verdade (só a mensagem 1), já aceito pela Meta.
  def button_notice(kind)
    notice = Crm::MeetingNotice.create!(meeting: meeting, account: account, kind: kind, status: :sending, attempts: 1,
                                        due_at: Crm::BookingV2::Notices::Scheduler.expected_due_at(meeting, kind))
    Crm::BookingV2::Notices::Sender.new(notice).perform
    Message.find(notice.reload.message_id).update!(source_id: "wamid.#{notice.id}")
    notice
  end

  def stop_of(notice)
    conversation.messages.outgoing.find { |message| stop_job.stop_part_of?(message, notice.id) }
  end

  def stop_alerts
    Crm::FollowUp.where(account_id: account.id).where("metadata->>'event' = ?", 'notice_stop_failed')
  end

  # Item 6 da revisão: o job se perdeu (crash entre o aviso e o enfileiramento, Redis fora). Passado o GRACE sem a 2, o
  # aviso com botão é marcado e o responsável avisado. Os outros ficam: o que tem a 2, o sem botão e o recente.
  it 'aviso com botão sem a 2 depois de 5 minutos: stop_part_failed e alerta; os outros ficam' do
    lost = button_notice('booked')
    healthy = button_notice('rescheduled').tap { |notice| stop_job.perform_now(notice.id, 1) }
    text_message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing)
    text_only = Crm::MeetingNotice.create!(meeting: meeting, account: account, kind: 'day_before', status: :sent, sent_at: Time.current,
                                           message_id: text_message.id,
                                           due_at: Crm::BookingV2::Notices::Scheduler.expected_due_at(meeting, 'day_before'))

    travel 2.minutes
    described_class.new.perform
    expect(lost.reload.error_code).to be_nil

    travel 4.minutes
    2.times { described_class.new.perform }

    expect(lost.reload).to have_attributes(status: 'sent', error_code: 'stop_part_failed')
    expect([healthy, text_only].map { |notice| notice.reload.error_code }).to eq([nil, nil])
    expect(stop_alerts.sole.metadata).to include('kind' => 'booked', 'reason' => 'stop_part_failed')
  end

  # Item 6: cliente que parou os avisos não precisa da 2, e ninguém é chamado por ela.
  it 'cliente que parou os avisos: sem marca e sem alerta' do
    lost = button_notice('booked')
    Crm::BookingNoticeStop.create!(account: account, contact: world.contact)

    travel 6.minutes
    described_class.new.perform

    expect(lost.reload.error_code).to be_nil
    expect(stop_alerts).to be_empty
  end

  # Item 8: em páginas pelo id, sem cortar casos. Com página de 1 e uma mensagem falha que não é a 2 (mesmo remetente)
  # antes delas, as duas 2 que falharam são achadas.
  it 'a 2 marcada failed depois: acha todas, em páginas, e ignora mensagem falha que não é a 2' do
    stub_const("#{described_class}::PAGE", 1)
    notices = %w[booked rescheduled].map { |kind| button_notice(kind) }
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, status: :failed,
                     sender: meeting.created_by)
    notices.each do |notice|
      stop_job.perform_now(notice.id, 1)
      stop_of(notice).update!(status: :failed)
    end

    described_class.new.perform

    expect(notices.map { |notice| notice.reload.attributes.slice('status', 'error_code') })
      .to all(eq('status' => 'sent', 'error_code' => 'stop_part_failed'))
    expect(stop_alerts.count).to eq(2)
  end
end
