require 'rails_helper'

# Cron de avisos (#1192, PLANO §2.5/§8): sai sem consultar com o calendário desligado, pega só pendentes vencidos,
# claim atômico, um aviso com erro não para os outros, `sending` preso vira `failed` sem reenviar e o sidekiq-cron
# consegue enfileirar (perform_later, sem método do ActiveJob sobrescrito).
RSpec.describe Crm::BookingV2::NoticeDispatchJob do
  let(:account) { create(:account) }
  let(:world) { build_booking_world(account: account) }
  let(:meeting) { create_internal_meeting(world: world, starts_at: 3.days.from_now) }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true') { example.run }
  end

  def notice(kind, due_at:, status: :pending, **attrs)
    Crm::MeetingNotice.create!(meeting: meeting, account: account, kind: kind, due_at: due_at, status: status, **attrs)
  end

  def failure_alerts
    Crm::FollowUp.where(account_id: account.id).where("metadata->>'event' = ?", 'notice_failed')
  end

  it 'enfileira como o sidekiq-cron faz' do
    expect { described_class.set(queue: 'scheduled_jobs').perform_later }.to have_enqueued_job(described_class).on_queue('scheduled_jobs')
  end

  it 'manda só os pendentes vencidos, marcando a tentativa' do
    due = notice('booked', due_at: 1.minute.ago)
    later = notice('day_before', due_at: 1.hour.from_now)
    done = notice('hour_before', due_at: 2.minutes.ago, status: :sent)
    sent_ids = []
    allow(Crm::BookingV2::Notices::Sender).to receive(:new) do |record|
      sent_ids << record.id
      expect(record.reload).to have_attributes(status: 'sending', attempts: 1)
      instance_double(Crm::BookingV2::Notices::Sender, perform: true)
    end

    described_class.perform_now

    expect(sent_ids).to eq([due.id])
    expect([later.reload.status, done.reload.status]).to eq(%w[pending sent])
  end

  it 'não consulta nada com o calendário de reuniões da instalação desligado' do
    notice('booked', due_at: 1.minute.ago)
    allow(Crm::MeetingNotice).to receive(:pending).and_call_original

    with_modified_env('CRM_CALENDAR_MEETINGS_ENABLED' => 'false') { described_class.perform_now }

    expect(Crm::MeetingNotice).not_to have_received(:pending)
  end

  it 'um aviso com erro inesperado vira failed e os outros seguem' do
    broken = notice('booked', due_at: 2.minutes.ago)
    fine = notice('day_before', due_at: 1.minute.ago)
    allow(Crm::BookingV2::Notices::Sender).to receive(:new) do |record|
      raise ActiveRecord::StatementInvalid, 'boom' if record.id == broken.id

      instance_double(Crm::BookingV2::Notices::Sender, perform: record.update!(status: :sent))
    end

    tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
    allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)

    described_class.perform_now

    expect(broken.reload).to have_attributes(status: 'failed', error_code: 'ActiveRecord::StatementInvalid')
    expect(fine.reload.status).to eq('sent')
    expect(ChatwootExceptionTracker).to have_received(:new).with(an_instance_of(ActiveRecord::StatementInvalid), account: account)
    expect(tracker).to have_received(:capture_exception).once
    expect(failure_alerts.sole).to have_attributes(assignee_id: world.host.id, card_id: world.card.id)
  end

  it 'aviso preso em sending há mais de 15 minutos vira failed interrupted, sem reenviar' do
    stuck = notice('booked', due_at: 1.hour.ago, status: :sending)
    stuck.update_columns(updated_at: 16.minutes.ago) # rubocop:disable Rails/SkipsModelValidations
    allow(Crm::BookingV2::Notices::Sender).to receive(:new)

    described_class.perform_now

    expect(stuck.reload).to have_attributes(status: 'failed', error_code: 'interrupted')
    expect(Crm::BookingV2::Notices::Sender).not_to have_received(:new)
    expect(failure_alerts.count).to eq(1)

    described_class.perform_now
    expect(failure_alerts.count).to eq(1)
  end

  describe 'falha de entrega informada depois pelo provedor (sent = mensagem criada)' do
    let(:conversation) { create(:conversation, account: account, contact: world.contact) }

    def sent_notice(kind, message_status:, sent_at: 10.minutes.ago)
      message = create(:message, account: account, inbox: conversation.inbox, conversation: conversation, message_type: :outgoing,
                                 status: message_status)
      notice(kind, due_at: sent_at, status: :sent, sent_at: sent_at, message_id: message.id)
    end

    it 'aviso cuja mensagem falhou vira failed delivery_failed e avisa o responsável uma vez' do
      failed = sent_notice('booked', message_status: :failed)
      delivered = sent_notice('day_before', message_status: :delivered)
      allow(Crm::BookingV2::Notices::Sender).to receive(:new)

      2.times { described_class.perform_now }

      expect(failed.reload).to have_attributes(status: 'failed', error_code: 'delivery_failed')
      expect(delivered.reload).to have_attributes(status: 'sent', error_code: nil)
      expect(failure_alerts.count).to eq(1)
      expect(Crm::Activity.where(card_id: world.card.id, event_type: 'booking_notice_failed').count).to eq(1)
    end

    it 'não reabre aviso enviado há mais de 2 horas' do
      old = sent_notice('booked', message_status: :failed, sent_at: 3.hours.ago)

      described_class.perform_now

      expect(old.reload.status).to eq('sent')
      expect(failure_alerts).to be_empty
    end
  end
end
