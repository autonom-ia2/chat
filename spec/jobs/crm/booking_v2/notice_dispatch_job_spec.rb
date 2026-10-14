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

    # Remetente fixo: a 2 sai sempre com o remetente da 1 (a factory sortearia um usuário por mensagem).
    def sent_notice(kind, message_status:, sent_at: 10.minutes.ago)
      message = create(:message, account: account, inbox: conversation.inbox, conversation: conversation, message_type: :outgoing,
                                 status: message_status, sender: meeting.created_by)
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

    # #1562: a mensagem 2 ("Parar avisos") do aviso com botão falhou depois, no provedor. A 1 saiu: o aviso fica sent
    # (não vira failed nem é reenviado), ganha stop_part_failed e o responsável é avisado UMA vez, mesmo com o cron
    # rodando de novo. A mensagem 2 de OUTRO aviso, ou a sem a marca, não conta. Pega quem confundisse a 2 com a 1.
    it 'mensagem 2 do aviso com botão que falhou: aviso continua sent, marcado, e o responsável é avisado uma vez' do
      split = sent_notice('booked', message_status: :sent)
      other = sent_notice('rescheduled', message_status: :sent)
      stop = lambda do |for_notice, part: 'stop'|
        create(:message, account: account, inbox: conversation.inbox, conversation: conversation, message_type: :outgoing, status: :failed,
                         sender: meeting.created_by,
                         content_attributes: { crm_booking_notice: true, crm_booking_notice_part: part, crm_booking_notice_id: for_notice.id })
      end
      stop.call(split)
      stop.call(other, part: 'other')
      allow(Crm::BookingV2::Notices::Sender).to receive(:new)
      stop_alerts = Crm::FollowUp.where(account_id: account.id).where("metadata->>'event' = ?", 'notice_stop_failed')

      expect { 2.times { described_class.perform_now } }.not_to change(Message, :count)

      expect(split.reload).to have_attributes(status: 'sent', error_code: 'stop_part_failed')
      expect(other.reload).to have_attributes(status: 'sent', error_code: nil)
      expect(stop_alerts.sole.metadata).to include('reason' => 'stop_part_failed', 'kind' => 'booked')
      expect(failure_alerts).to be_empty
      expect(Crm::Activity.where(card_id: world.card.id, event_type: 'booking_notice_failed').count).to eq(1)
    end

    # #1562: em páginas pelo par (mensagem, aviso), sem cortar casos. Com página de 1 e uma mensagem falha que não é a 2
    # (mesmo remetente) antes delas, as duas 2 que falharam são achadas.
    it 'a 2 que falhou é achada em páginas, sem perder casos, e mensagem falha sem a marca não conta' do
      stub_const("#{described_class}::BATCH", 1)
      notices = %w[booked rescheduled].map { |kind| sent_notice(kind, message_status: :sent) }
      create(:message, account: account, inbox: conversation.inbox, conversation: conversation, message_type: :outgoing, status: :failed,
                       sender: meeting.created_by)
      notices.each do |item|
        create(:message, account: account, inbox: conversation.inbox, conversation: conversation, message_type: :outgoing, status: :failed,
                         sender: meeting.created_by,
                         content_attributes: { crm_booking_notice: true, crm_booking_notice_part: 'stop', crm_booking_notice_id: item.id })
      end
      allow(Crm::BookingV2::Notices::Sender).to receive(:new)

      described_class.perform_now

      expect(notices.map { |item| item.reload.attributes.slice('status', 'error_code') })
        .to all(eq('status' => 'sent', 'error_code' => 'stop_part_failed'))
    end

    # #1562: se a mensagem 1 falhou, vale o delivery_failed de sempre (o aviso não saiu), com ou sem a 2.
    it 'mensagem 1 que falhou continua delivery_failed, mesmo com a mensagem 2 falhando também' do
      split = sent_notice('booked', message_status: :failed)
      create(:message, account: account, inbox: conversation.inbox, conversation: conversation, message_type: :outgoing, status: :failed,
                       content_attributes: { crm_booking_notice: true, crm_booking_notice_part: 'stop', crm_booking_notice_id: split.id })

      described_class.perform_now

      expect(split.reload).to have_attributes(status: 'failed', error_code: 'delivery_failed')
      expect(failure_alerts.count).to eq(1)
    end

    it 'não reabre aviso enviado há mais de 2 horas' do
      old = sent_notice('booked', message_status: :failed, sent_at: 3.hours.ago)

      described_class.perform_now

      expect(old.reload.status).to eq('sent')
      expect(failure_alerts).to be_empty
    end
  end

  it 'avisos que esperam a WAHA vão para o fim do lote, o tentado há mais tempo primeiro (#1270)' do
    waiting_recent = notice('booked', due_at: 3.hours.ago, error_code: 'waha_unavailable', updated_at: 1.minute.ago)
    waiting_old = notice('rescheduled', due_at: 2.hours.ago, error_code: 'waha_unavailable', updated_at: 5.minutes.ago)
    fresh_late = notice('hour_before', due_at: 1.minute.ago)
    fresh_early = notice('day_before', due_at: 10.minutes.ago)
    order = []
    allow(Crm::BookingV2::Notices::Sender).to receive(:new) do |record|
      order << record.id
      instance_double(Crm::BookingV2::Notices::Sender, perform: true)
    end

    described_class.perform_now

    expect(order).to eq([fresh_early.id, fresh_late.id, waiting_old.id, waiting_recent.id])
  end

  # #1270: WAHA fora do ar numa rodada. A caixa é consultada uma vez só; os avisos dela voltam à fila e saem na rodada
  # em que a WAHA volta.
  describe 'caixa WAHA fora do ar' do
    let(:inbox) do
      create(:channel_api, account: account, additional_attributes: { 'provider' => 'waha', 'session' => '5511900001111' }).inbox
    end
    let(:check_url) { 'https://waha.test/api/contacts/check-exists' }
    let(:meeting) do
      create_internal_meeting(world: world, starts_at: 3.days.from_now, metadata: { 'booking_profile_id' => world.profile.id })
    end

    around do |example|
      with_modified_env('WAHA_API_URL' => 'https://waha.test', 'WAHA_API_KEY' => 'chave-waha-teste',
                        'FRONTEND_URL' => 'https://app.example.com') { example.run }
    end

    before do
      account.enable_features('crm_booking_v2')
      account.save!
      world.profile.update!(notice_inbox: inbox)
      create_booking_invite(world: world, meeting: meeting, scheduled_at: Time.current, channel: 'public')
    end

    it 'consulta a WAHA uma vez na rodada, devolve os avisos à fila sem alertar e manda quando ela volta' do
      first = notice('booked', due_at: 2.minutes.ago)
      second = notice('rescheduled', due_at: 1.minute.ago)
      down = stub_request(:get, check_url).with(query: hash_including(session: '5511900001111')).to_timeout

      described_class.perform_now

      expect(down).to have_been_made.once
      expect([first, second].map { |item| item.reload.status }).to eq(%w[pending pending])
      expect(failure_alerts).to be_empty

      WebMock.reset!
      stub_request(:get, check_url).with(query: hash_including(session: '5511900001111'))
                                   .to_return(status: 200, body: { numberExists: true, chatId: '5511912345678@c.us' }.to_json,
                                              headers: { 'Content-Type' => 'application/json' })

      described_class.perform_now

      expect([first, second].map { |item| item.reload.status }).to eq(%w[sent sent])
      expect(first.reload.attempts).to eq(2)
      expect(failure_alerts).to be_empty
    end
  end
end
