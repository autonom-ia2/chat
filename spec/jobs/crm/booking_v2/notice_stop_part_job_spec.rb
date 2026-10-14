require 'rails_helper'

# Mensagem 2 do aviso com botão (#1562), criada por um job atrasado depois que a 1 saiu: cada mensagem tem o próprio
# SendReplyJob, e criar as duas juntas deixava a 2 ("Parar avisos") chegar antes do aviso.
RSpec.describe Crm::BookingV2::NoticeStopPartJob do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:world) { build_booking_world(account: account) }
  let(:inbox) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false).inbox
  end
  let(:meeting) do
    create_internal_meeting(world: world, starts_at: Time.zone.parse('2026-10-20T13:00:00Z'),
                            metadata: { 'booking_profile_id' => world.profile.id })
  end
  let!(:invite) { create_booking_invite(world: world, meeting: meeting, scheduled_at: Time.current, channel: 'public') }
  let!(:conversation) do
    create(:conversation, account: account, inbox: inbox, contact: world.contact).tap do |item|
      create(:message, account: account, inbox: inbox, conversation: item, message_type: :incoming, created_at: 2.hours.ago)
    end
  end

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true', 'FRONTEND_URL' => 'https://app.example.com') do
      travel_to(Time.zone.parse('2026-10-12T14:00:00Z')) { example.run }
    end
  end

  before do
    account.enable_features('crm_booking_v2')
    account.save!
    world.profile.update!(notice_inbox: inbox)
  end

  # O aviso com botão pelo Sender de verdade: só a mensagem 1 é criada.
  def sent_notice(kind = 'booked')
    notice = Crm::MeetingNotice.create!(meeting: meeting, account: account, kind: kind, status: :sending, attempts: 1,
                                        due_at: Crm::BookingV2::Notices::Scheduler.expected_due_at(meeting, kind))
    Crm::BookingV2::Notices::Sender.new(notice).perform
    notice.reload
  end

  def first_message(notice)
    Message.find(notice.message_id)
  end

  def accepted!(notice)
    first_message(notice).update!(source_id: "wamid.#{notice.id}")
  end

  def stop_messages
    conversation.messages.outgoing.order(:id).select { |message| message.content_attributes['crm_booking_notice_part'] == 'stop' }
  end

  def stop_alerts
    Crm::FollowUp.where(account_id: account.id).where("metadata->>'event' = ?", 'notice_stop_failed')
  end

  # Ordem: a 2 só nasce depois que a Meta aceitou a 1 (wamid), e vem depois dela, na mesma conversa e do mesmo
  # remetente. Pega quem criasse a 2 sem esperar a 1 sair.
  it 'a 1 saiu: cria a 2 depois dela, na mesma conversa, do mesmo remetente, com a marca' do
    notice = sent_notice
    accepted!(notice)

    described_class.perform_now(notice.id, 1)

    first = first_message(notice)
    stop = stop_messages.sole
    expect(stop).to have_attributes(id: be > first.id, conversation_id: first.conversation_id, sender: meeting.created_by,
                                    content: 'Não quer mais receber estes avisos?')
    expect(stop.content_attributes).to include(
      'crm_booking_notice_id' => notice.id,
      'rich_message' => { 'type' => 'link_button', 'label' => 'Parar avisos', 'url' => "#{invite.url}?stop_notices=1" }
    )
    expect(notice.reload).to have_attributes(status: 'sent', message_id: first.id, error_code: nil)
  end

  # Ordem: a 1 ainda não saiu (sem wamid) → a 2 espera, reagendada, e não é criada.
  it 'a 1 ainda não saiu: não cria a 2 e reagenda com a próxima tentativa' do
    notice = sent_notice

    expect { described_class.perform_now(notice.id, 1) }.not_to change(Message, :count)

    expect(described_class).to have_been_enqueued.with(notice.id, 2).at(described_class::WAIT.from_now)
    expect(stop_alerts).to be_empty
  end

  # A 1 nunca saiu: depois de MAX_ATTEMPTS desiste, sem criar nada, e avisa o responsável uma vez.
  it 'a 1 não sai até a última tentativa: desiste com stop_part_failed e um alerta' do
    notice = sent_notice

    2.times { described_class.perform_now(notice.id, described_class::MAX_ATTEMPTS) }

    expect(stop_messages).to be_empty
    expect(notice.reload).to have_attributes(status: 'sent', error_code: 'stop_part_failed')
    expect(stop_alerts.sole.metadata).to include('reason' => 'stop_part_failed', 'kind' => 'booked')
  end

  # Idempotência: o job rodando de novo (retry, duplicata do Sidekiq) não manda a 2 duas vezes.
  it 'não duplica a 2 quando roda de novo' do
    notice = sent_notice
    accepted!(notice)

    2.times { described_class.perform_now(notice.id, 1) }

    expect(stop_messages.size).to eq(1)
  end

  # 1 failed: a 2 não sai (o cliente não recebeu o aviso), e o responsável é avisado pelo delivery_failed de sempre.
  it 'a 1 falhou: a 2 não sai e o cron avisa o responsável' do
    notice = sent_notice
    first_message(notice).update!(status: :failed)

    described_class.perform_now(notice.id, 1)
    Crm::BookingV2::NoticeDispatchJob.perform_now

    expect(stop_messages).to be_empty
    expect(notice.reload).to have_attributes(status: 'failed', error_code: 'delivery_failed')
    expect(Crm::FollowUp.where(account_id: account.id).where("metadata->>'event' = ?", 'notice_failed').count).to eq(1)
  end

  # Erro ao criar a 2: a 1 fica e não é refeita; o aviso continua sent, marcado, e o responsável é avisado UMA vez por
  # reunião (o segundo aviso com o mesmo problema não cria outra tarefa).
  it 'erro ao criar a 2: a 1 fica, o aviso continua sent e o responsável é avisado uma vez' do
    notices = %w[booked rescheduled].map { |kind| sent_notice(kind).tap { |notice| accepted!(notice) } }
    allow(Crm::BookingV2::Notices::Delivery).to receive(:new).and_raise(ActiveRecord::RecordInvalid)
    tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
    allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)

    notices.each { |notice| described_class.perform_now(notice.id, 1) }

    expect(notices.map { |notice| notice.reload.attributes.slice('status', 'error_code') })
      .to all(eq('status' => 'sent', 'error_code' => 'stop_part_failed'))
    expect(conversation.messages.outgoing.count).to eq(2)
    expect(stop_alerts.sole).to have_attributes(assignee_id: meeting.created_by_id)
    expect(stop_alerts.sole.title).to include('saiu, mas a mensagem com o botão "Parar avisos" não')
    expect(tracker).to have_received(:capture_exception).twice
  end

  # Aviso que já não é sent (remarcado, falhou) ou já marcado: nada a fazer.
  it 'ignora aviso que não está mais sent' do
    notice = sent_notice
    accepted!(notice)
    notice.update!(status: :pending)

    expect { described_class.perform_now(notice.id, 1) }.not_to change(Message, :count)
  end
end
