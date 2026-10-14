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

  # Erro ao criar a 2: a 1 fica e não é refeita; o aviso continua sent, marcado, e o responsável é avisado uma vez POR
  # AVISO (item 9 da revisão: dois avisos da mesma reunião são dois alertas; o mesmo aviso de novo, nenhum a mais).
  it 'erro ao criar a 2: a 1 fica, o aviso continua sent e o responsável é avisado uma vez por aviso' do
    notices = %w[booked rescheduled].map { |kind| sent_notice(kind).tap { |notice| accepted!(notice) } }
    allow(Crm::BookingV2::Notices::Delivery).to receive(:new).and_raise(ActiveRecord::RecordInvalid)
    tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
    allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)

    notices.each { |notice| described_class.perform_now(notice.id, 1) }
    described_class.stop_failed!(notices.first.reload, why: 'again')

    expect(notices.map { |notice| notice.reload.attributes.slice('status', 'error_code') })
      .to all(eq('status' => 'sent', 'error_code' => 'stop_part_failed'))
    expect(conversation.messages.outgoing.count).to eq(2)
    expect(stop_alerts.map { |alert| alert.metadata['kind'] }).to contain_exactly('booked', 'rescheduled')
    expect(stop_alerts.first.title).to include('saiu, mas a mensagem com o botão "Parar avisos" não')
    expect(tracker).to have_received(:capture_exception).twice
  end

  # Item 1 da revisão: erro ao carregar o aviso não pode sumir em silêncio. Vai ao log e ao tracker e, sendo de banco,
  # relança para o retry do Sidekiq (a conferência e o error_code seguram a repetição).
  it 'erro de banco ao carregar o aviso: log, tracker e relança para o retry' do
    notice = sent_notice
    accepted!(notice)
    allow(Crm::MeetingNotice).to receive(:includes).and_raise(ActiveRecord::ConnectionNotEstablished)
    tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
    allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)
    allow(Rails.logger).to receive(:error)

    expect { described_class.perform_now(notice.id, 1) }.to raise_error(ActiveRecord::ConnectionNotEstablished)

    expect(tracker).to have_received(:capture_exception)
    expect(Rails.logger).to have_received(:error).with(include("CRM booking notice #{notice.id} stop part error"))
  end

  # Item 1: erro que não é de banco depois de carregar: o aviso é relido por id no rescue e o responsável é avisado.
  it 'erro inesperado: relê o aviso por id, marca stop_part_failed e avisa' do
    notice = sent_notice
    accepted!(notice)
    allow(Message).to receive(:find_by).and_raise(NoMethodError)
    allow(ChatwootExceptionTracker).to receive(:new).and_return(instance_double(ChatwootExceptionTracker, capture_exception: true))

    described_class.perform_now(notice.id, 1)

    expect(notice.reload.error_code).to eq('stop_part_failed')
    expect(stop_alerts.count).to eq(1)
  end

  # Item 2: a mensagem 1 apagada não pode deixar o aviso sem a 2 e sem ninguém saber.
  it 'mensagem 1 apagada: stop_part_failed e alerta' do
    notice = sent_notice
    first_message(notice).destroy!

    described_class.perform_now(notice.id, 1)

    expect(notice.reload.error_code).to eq('stop_part_failed')
    expect(stop_alerts.count).to eq(1)
  end

  # Item 3: o cliente parou os avisos (ou a reunião foi cancelada) depois da 1: a 2 não sai e ninguém é chamado.
  it 'cliente parou os avisos ou reunião cancelada: não cria a 2 e não alerta' do
    stopped = sent_notice('booked')
    accepted!(stopped)
    Crm::BookingNoticeStop.create!(account: account, contact: world.contact)
    described_class.perform_now(stopped.id, 1)
    Crm::BookingNoticeStop.where(contact_id: world.contact.id).delete_all

    canceled = sent_notice('rescheduled')
    accepted!(canceled)
    meeting.update!(status: :canceled)
    described_class.perform_now(canceled.id, 1)

    expect(stop_messages).to be_empty
    expect([stopped, canceled].map { |notice| notice.reload.error_code }).to eq([nil, nil])
    expect(stop_alerts).to be_empty
  end

  # Item 4: a conferência de duplicata não pode ter corte de quantidade. Com 60 mensagens entre a 1 e a 2 (o corte
  # antigo era 50), rodar de novo não cria outra.
  it 'não duplica a 2 mesmo com muitas mensagens na conversa depois dela' do
    notice = sent_notice
    accepted!(notice)
    described_class.perform_now(notice.id, 1)
    create_list(:message, 60, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing)

    described_class.perform_now(notice.id, 1)

    expect(stop_messages.size).to eq(1)
  end

  # Item 4: passada a WINDOW o job não cria mais a 2 (a conferência só cobre a WINDOW): desiste com alerta.
  it 'tarde demais (depois da WINDOW): não cria a 2 e avisa' do
    notice = sent_notice
    accepted!(notice)

    travel described_class::WINDOW + 1.minute
    described_class.perform_now(notice.id, 1)

    expect(stop_messages).to be_empty
    expect(notice.reload.error_code).to eq('stop_part_failed')
  end

  # Os retries do Sidekiq (erro de banco) passam da WINDOW. O que chega depois dela, com o banco de volta, desiste com
  # um alerta em vez de relançar de novo ou criar a 2 fora da conferência; o seguinte não faz mais nada.
  it 'retry depois da WINDOW: stop_failed! com um alerta, sem relançar nem criar a 2' do
    notice = sent_notice
    calls = 0
    allow(Crm::MeetingNotice).to receive(:includes).and_wrap_original do |original, *args|
      calls += 1
      raise ActiveRecord::ConnectionNotEstablished if calls == 1

      original.call(*args)
    end
    allow(ChatwootExceptionTracker).to receive(:new).and_return(instance_double(ChatwootExceptionTracker, capture_exception: true))
    expect { described_class.perform_now(notice.id, 1) }.to raise_error(ActiveRecord::ConnectionNotEstablished)

    travel described_class::WINDOW + 1.minute
    2.times { expect { described_class.perform_now(notice.id, 1) }.not_to raise_error }

    expect(stop_messages).to be_empty
    expect(notice.reload).to have_attributes(status: 'sent', error_code: 'stop_part_failed')
    expect(stop_alerts.count).to eq(1)
  end

  # Item 5: o alerta falhando não derruba nada e não desfaz a marca: fica no log e no tracker.
  it 'alerta que falha: a marca fica e o erro vai ao tracker' do
    notice = sent_notice
    tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
    allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)
    allow(Crm::BookingV2::Notices::AgentAlert).to receive(:new).and_raise(ActiveRecord::RecordInvalid)

    expect { described_class.stop_failed!(notice, why: 'gave_up') }.not_to raise_error

    expect(notice.reload.error_code).to eq('stop_part_failed')
    expect(tracker).to have_received(:capture_exception)
  end

  # Item 7: mensagem ausente (nil) não é a 2 e não derruba quem confere.
  it 'stop_part_of? com mensagem ausente é falso' do
    expect(described_class.stop_part_of?(nil, 1)).to be(false)
  end

  # Aviso que já não é sent (remarcado, falhou) ou já marcado: nada a fazer.
  it 'ignora aviso que não está mais sent' do
    notice = sent_notice
    accepted!(notice)
    notice.update!(status: :pending)

    expect { described_class.perform_now(notice.id, 1) }.not_to change(Message, :count)
  end
end
