require 'rails_helper'

# Envio dos avisos (#1192): J5-A1 (texto dentro da janela, modelo aprovado fora), J5-A4 (falha registra e avisa,
# nunca altera a reunião), J5-A5 (WAHA só dentro da janela), J2-A9/RA-18 (toda mensagem tem como parar, quem parou
# não recebe), tetos e kill-switch.
RSpec.describe Crm::BookingV2::Notices::Sender do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:world) { build_booking_world(account: account) }
  let(:booked_template) do
    { 'name' => 'aviso_marcado', 'status' => 'APPROVED', 'language' => 'pt_BR', 'category' => 'UTILITY',
      'components' => [{ 'type' => 'BODY', 'text' => 'Oi {{1}}, seu horário é {{2}}. Gerencie aqui: {{3}}' }] }
  end
  let(:inbox) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false,
                              message_templates: [booked_template]).inbox
  end
  let(:meeting) do
    create_internal_meeting(world: world, starts_at: Time.zone.parse('2026-10-20T13:00:00Z'),
                            metadata: { 'booking_profile_id' => world.profile.id })
  end
  let!(:invite) { create_booking_invite(world: world, meeting: meeting, scheduled_at: Time.current, channel: 'public') }

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

  # Aviso já tomado pelo cron, no vencimento que o Scheduler daria (lembrete: início menos a antecedência).
  def claimed(kind = 'booked', due_at: Crm::BookingV2::Notices::Scheduler.expected_due_at(meeting, kind))
    Crm::MeetingNotice.create!(meeting: meeting, account: account, kind: kind, due_at: due_at, status: :sending, attempts: 1)
  end

  def open_window!(at: 2.hours.ago, target_inbox: inbox)
    conversation = create(:conversation, account: account, inbox: target_inbox, contact: world.contact)
    create(:message, account: account, inbox: target_inbox, conversation: conversation, message_type: :incoming, created_at: at)
    conversation
  end

  def alerts
    Crm::FollowUp.where(account_id: account.id).where("metadata->>'source' = ?", 'booking_agent_alert')
  end

  def meeting_snapshot
    meeting.reload.attributes.slice('status', 'starts_at', 'ends_at', 'confirmation_status', 'reminders_stopped_at')
  end

  describe 'WhatsApp oficial (J5-A1)' do
    it 'manda texto dentro da janela de 24 h, com link de gestão e linha de parar (J2-A9)' do
      conversation = open_window!
      notice = claimed

      described_class.new(notice).perform

      message = Message.find(notice.reload.message_id)
      expect(notice).to have_attributes(status: 'sent', sent_at: Time.current, skip_reason: nil, error_code: nil)
      expect(message).to have_attributes(conversation_id: conversation.id, message_type: 'outgoing')
      expect(message.additional_attributes.to_h['template_params']).to be_nil
      expect(message.content).to eq(
        "Oi, Marcos! Seu horário está marcado para 20/10 às 10:00. Para confirmar, mudar ou cancelar: #{invite.url}\n\n" \
        "Para parar estes avisos: #{invite.url}?stop_notices=1"
      )
      expect(message.content_attributes['crm_booking_notice']).to be(true)
    end

    it 'fora da janela manda o modelo aprovado, com as três variáveis, numa conversa nova se não houver' do
      world.profile.update!(notice_templates: { 'booked' => { 'name' => 'aviso_marcado', 'language' => 'pt_BR' } })
      notice = claimed

      expect { described_class.new(notice).perform }.to change(Conversation, :count).by(1)

      message = Message.find(notice.reload.message_id)
      expect(notice.status).to eq('sent')
      expect(message.conversation).to have_attributes(inbox_id: inbox.id, contact_id: world.contact.id)
      expect(message.additional_attributes['template_params']).to eq(
        'name' => 'aviso_marcado', 'language' => 'pt_BR',
        'processed_params' => { 'body' => { '1' => 'Marcos', '2' => '20/10 às 10:00', '3' => invite.url } }
      )
      expect(message.content).to eq("Oi Marcos, seu horário é 20/10 às 10:00. Gerencie aqui: #{invite.url}")
    end

    it 'fora da janela e sem modelo aprovado pula com template_required, avisa o agente uma vez e não mexe na reunião (J2-A6, J5-A4)' do
      before = meeting_snapshot
      first = claimed('booked')
      second = claimed('day_before')

      expect do
        described_class.new(first).perform
        described_class.new(second).perform
      end.not_to change(Message, :count)

      expect([first.reload, second.reload].map { |notice| [notice.status, notice.skip_reason] }).to eq([%w[skipped template_required]] * 2)
      expect(alerts.count).to eq(1)
      expect(alerts.sole).to have_attributes(assignee_id: world.host.id, follow_up_type: 'task', card_id: world.card.id)
      failures = Crm::Activity.where(card_id: world.card.id, event_type: 'booking_notice_failed')
      expect(failures.count).to eq(2)
      expect(failures.map { |activity| activity.payload['by'] }).to eq(%w[system system])
      expect(meeting_snapshot).to eq(before)
    end

    it 'modelo aprovado sem {{3}} (sem link de gestão nem de parar) não sai: template_without_link e avisa o agente (J2-A9, RA-18)' do
      no_link = booked_template.merge('components' => [{ 'type' => 'BODY', 'text' => 'Oi {{1}}, seu horário é {{2}}.' }])
      inbox.channel.update!(message_templates: [no_link])
      world.profile.update_columns(notice_templates: { 'booked' => { 'name' => 'aviso_marcado', 'language' => 'pt_BR' } }) # rubocop:disable Rails/SkipsModelValidations
      notice = claimed

      expect { described_class.new(notice).perform }.not_to change(Message, :count)

      expect(notice.reload).to have_attributes(status: 'skipped', skip_reason: 'template_without_link')
      expect(alerts.count).to eq(1)
    end

    it 'modelo configurado mas NÃO aprovado na Meta conta como sem modelo' do
      inbox.channel.update!(message_templates: [booked_template.merge('status' => 'PENDING')])
      world.profile.update!(notice_templates: { 'booked' => { 'name' => 'aviso_marcado', 'language' => 'pt_BR' } })
      notice = claimed

      described_class.new(notice).perform

      expect(notice.reload).to have_attributes(status: 'skipped', skip_reason: 'template_required')
    end
  end

  describe 'WAHA (J5-A5)' do
    let(:inbox) { create(:channel_api, account: account, additional_attributes: { 'provider' => 'waha' }).inbox }

    it 'não manda sem mensagem do cliente nas últimas 24 h, mesmo com conversa' do
      open_window!(at: 25.hours.ago)
      notice = claimed

      expect { described_class.new(notice).perform }.not_to change(Message.outgoing, :count)

      expect(notice.reload).to have_attributes(status: 'skipped', skip_reason: 'waha_outside_window')
      expect(alerts.count).to eq(1)
    end

    it 'manda texto quando o cliente escreveu há menos de 24 h' do
      conversation = open_window!(at: 23.hours.ago)
      notice = claimed

      described_class.new(notice).perform

      expect(notice.reload.status).to eq('sent')
      expect(Message.find(notice.message_id).conversation_id).to eq(conversation.id)
    end
  end

  describe 'canal API de campanhas, não WAHA' do
    let(:inbox) do
      create(:channel_api, account: account,
                           additional_attributes: { 'campaign_channel_type' => 'whatsapp_api', 'whatsapp_api_provider' => 'evolution' }).inbox
    end
    let!(:api_template) do
      account.whatsapp_api_message_templates.create!(inbox: inbox, name: 'lembrete', created_by: world.host,
                                                     body: 'Oi {{contact.first_name}}, lembrete do seu horário.')
    end

    it 'fora da janela manda o modelo do canal por id, com dia, link e linha de parar' do
      world.profile.update!(notice_templates: { 'booked' => { 'id' => api_template.id } })
      notice = claimed

      described_class.new(notice).perform

      expect(Message.find(notice.reload.message_id).content).to eq(
        "Oi Marcos, lembrete do seu horário.\n\n20/10 às 10:00 - #{invite.url}\n\nPara parar estes avisos: #{invite.url}?stop_notices=1"
      )
    end

    it 'sem modelo e fora da janela pula com template_required' do
      notice = claimed

      described_class.new(notice).perform

      expect(notice.reload).to have_attributes(status: 'skipped', skip_reason: 'template_required')
    end
  end

  describe 'parada (J5-A7, RA-18), na precedência opted_out, parar avisos, reunião parada' do
    before { open_window! }

    it 'contato que recusou mensagens ativas não recebe' do
      world.contact.update!(opted_out_at: Time.current, opt_out_source: 'manual')
      Crm::BookingNoticeStop.create!(account: account, contact: world.contact)
      notice = claimed

      described_class.new(notice).perform

      expect(notice.reload).to have_attributes(status: 'skipped', skip_reason: 'opted_out')
      expect(alerts).to be_empty
    end

    it 'contato que parou os avisos não recebe, em reunião nenhuma' do
      Crm::BookingNoticeStop.create!(account: account, contact: world.contact)
      notice = claimed

      expect { described_class.new(notice).perform }.not_to change(Message.outgoing, :count)

      expect(notice.reload).to have_attributes(status: 'skipped', skip_reason: 'stopped')
    end

    it 'reunião com avisos parados não recebe' do
      meeting.update!(reminders_stopped_at: Time.current)
      notice = claimed

      described_class.new(notice).perform

      expect(notice.reload).to have_attributes(status: 'skipped', skip_reason: 'stopped')
    end
  end

  describe 'reunião e conta' do
    before { open_window! }

    it 'reunião cancelada não recebe aviso e não chama o agente' do
      meeting.update!(status: :canceled)
      notice = claimed('day_before')

      described_class.new(notice).perform

      expect(notice.reload).to have_attributes(status: 'skipped', skip_reason: 'canceled')
      expect(alerts).to be_empty
    end

    it 'lembrete de reunião que já começou não sai' do
      meeting.update_columns(starts_at: 1.minute.ago, ends_at: 29.minutes.from_now) # rubocop:disable Rails/SkipsModelValidations
      notice = claimed('hour_before')

      described_class.new(notice).perform

      expect(notice.reload).to have_attributes(status: 'skipped', skip_reason: 'past_due')
    end

    it '"ao marcar" e "remarcado" atrasados não saem depois do início da reunião, sem chamar o agente' do
      meeting.update_columns(starts_at: 1.minute.ago, ends_at: 29.minutes.from_now) # rubocop:disable Rails/SkipsModelValidations
      notices = %w[booked rescheduled].map { |kind| claimed(kind, due_at: 20.minutes.ago) }

      expect { notices.each { |notice| described_class.new(notice).perform } }.not_to change(Message, :count)

      expect(notices.map { |notice| notice.reload.skip_reason }).to eq(%w[past_due past_due])
      expect(alerts).to be_empty
    end

    it 'lembrete cujo vencimento não bate mais com o início da reunião não sai (stale), sem chamar o agente' do
      notice = claimed('hour_before', due_at: meeting.starts_at - 3.hours)

      expect { described_class.new(notice).perform }.not_to change(Message, :count)

      expect(notice.reload).to have_attributes(status: 'skipped', skip_reason: 'stale')
      expect(alerts).to be_empty
    end

    it 'flag da conta desligada é o kill-switch: nada sai' do
      account.disable_features('crm_booking_v2')
      account.save!
      notice = claimed

      expect { described_class.new(notice).perform }.not_to change(Message.outgoing, :count)

      expect(notice.reload).to have_attributes(status: 'skipped', skip_reason: 'disabled')
    end

    it 'página sem caixa de avisos pula com no_inbox e avisa o agente' do
      world.profile.update!(notice_inbox: nil)
      notice = claimed

      described_class.new(notice).perform

      expect(notice.reload).to have_attributes(status: 'skipped', skip_reason: 'no_inbox')
      expect(alerts.count).to eq(1)
    end
  end

  describe 'tetos' do
    before { open_window! }

    # Avisos já enviados ao mesmo contato em outras reuniões dele (o teto é por número, não por reunião).
    def sent_elsewhere(count, at:)
      count.times do |index|
        other = create_internal_meeting(world: world, starts_at: Time.zone.parse('2026-10-25T13:00:00Z') + index.days)
        Crm::MeetingNotice.create!(meeting: other, account: account, kind: 'booked', due_at: at, status: :sent, sent_at: at)
      end
    end

    it 'para no 5º aviso automático ao mesmo número em 24 h, somando os testes de "Testar no meu WhatsApp"' do
      sent_elsewhere(3, at: 2.hours.ago)
      create_booking_invite(world: world, metadata: { 'test' => true }, sent_at: 1.hour.ago)
      notice = claimed

      described_class.new(notice).perform

      expect(notice.reload).to have_attributes(status: 'skipped', skip_reason: 'number_cap')
    end

    it 'aviso de mais de 24 h não conta' do
      sent_elsewhere(4, at: 25.hours.ago)
      notice = claimed

      described_class.new(notice).perform

      expect(notice.reload.status).to eq('sent')
    end

    it 'o próprio aviso (já em sending) não conta no teto' do
      sent_elsewhere(3, at: 2.hours.ago)
      notice = claimed

      described_class.new(notice).perform

      expect(notice.reload.status).to eq('sent')
    end

    it 'aviso saindo agora em outro processo (sending) conta no teto' do
      sent_elsewhere(3, at: 2.hours.ago)
      other = create_internal_meeting(world: world, starts_at: Time.zone.parse('2026-10-30T13:00:00Z'))
      Crm::MeetingNotice.create!(meeting: other, account: account, kind: 'booked', due_at: Time.current, status: :sending)
      notice = claimed

      described_class.new(notice).perform

      expect(notice.reload).to have_attributes(status: 'skipped', skip_reason: 'number_cap')
    end

    it 'teto por conta soma avisos saindo agora e testes' do
      other = create_internal_meeting(world: world, starts_at: Time.zone.parse('2026-10-21T13:00:00Z'))
      Crm::MeetingNotice.create!(meeting: other, account: account, kind: 'booked', due_at: Time.current, status: :sending)
      create_booking_invite(world: world, metadata: { 'test' => true }, sent_at: 1.hour.ago)
      notice = claimed

      with_modified_env('CRM_BOOKING_NOTICES_ACCOUNT_DAILY_LIMIT' => '2') { described_class.new(notice).perform }

      expect(notice.reload).to have_attributes(status: 'skipped', skip_reason: 'account_cap')
    end

    it 'respeita o teto por conta configurado no ambiente' do
      other = create_internal_meeting(world: world, starts_at: Time.zone.parse('2026-10-21T13:00:00Z'))
      Crm::MeetingNotice.create!(meeting: other, account: account, kind: 'booked', due_at: 1.hour.ago, status: :sent, sent_at: 1.hour.ago)
      notice = claimed

      with_modified_env('CRM_BOOKING_NOTICES_ACCOUNT_DAILY_LIMIT' => '1') { described_class.new(notice).perform }

      expect(notice.reload).to have_attributes(status: 'skipped', skip_reason: 'account_cap')
    end
  end

  it 'erro do envio vira failed com a classe do erro, avisa o agente e não altera a reunião (J5-A4)' do
    open_window!
    before = meeting_snapshot
    notice = claimed
    allow(Autonomia::LiteralMessageBuilder).to receive(:new).and_raise(ActiveRecord::RecordInvalid)
    tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
    allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)

    described_class.new(notice).perform

    expect(notice.reload).to have_attributes(status: 'failed', error_code: 'ActiveRecord::RecordInvalid', message_id: nil)
    expect(ChatwootExceptionTracker).to have_received(:new).with(an_instance_of(ActiveRecord::RecordInvalid), account: account)
    expect(tracker).to have_received(:capture_exception).once
    expect(alerts.count).to eq(1)
    expect(meeting_snapshot).to eq(before)
  end

  describe '#will_send? (J2-A6)' do
    it 'é verdadeiro só quando o aviso de fato sairia, sem enviar nada' do
      notice = Crm::MeetingNotice.create!(meeting: meeting, account: account, kind: 'booked', due_at: Time.current)

      expect(described_class.new(notice).will_send?).to be(false)
      open_window!
      expect { expect(described_class.new(notice).will_send?).to be(true) }.not_to change(Message, :count)
      expect(notice.reload.status).to eq('pending')
    end
  end
end
