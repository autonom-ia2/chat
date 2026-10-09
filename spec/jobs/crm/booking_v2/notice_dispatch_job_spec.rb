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

  def notice(kind, due_at:, status: :pending)
    Crm::MeetingNotice.create!(meeting: meeting, account: account, kind: kind, due_at: due_at, status: status)
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

    described_class.perform_now

    expect(broken.reload).to have_attributes(status: 'failed', error_code: 'ActiveRecord::StatementInvalid')
    expect(fine.reload.status).to eq('sent')
  end

  it 'aviso preso em sending há mais de 15 minutos vira failed interrupted, sem reenviar' do
    stuck = notice('booked', due_at: 1.hour.ago, status: :sending)
    stuck.update_columns(updated_at: 16.minutes.ago) # rubocop:disable Rails/SkipsModelValidations
    allow(Crm::BookingV2::Notices::Sender).to receive(:new)

    described_class.perform_now

    expect(stuck.reload).to have_attributes(status: 'failed', error_code: 'interrupted')
    expect(Crm::BookingV2::Notices::Sender).not_to have_received(:new)
  end
end
