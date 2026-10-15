require 'rails_helper'

# "Parar avisos" tocado no modelo v2 do aviso (#1524): para os avisos do contato, como o link de gestão, mas só quando
# a resposta prova (pelo `in_reply_to` na mesma conversa) que responde a um aviso nosso. Nada de ler o texto.
RSpec.describe Crm::BookingNoticeStopReplyListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:world) { build_booking_world(account: account) }
  let(:inbox) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false).inbox
  end
  let(:meeting) do
    create_internal_meeting(world: world, starts_at: Time.zone.parse('2026-10-20T13:00:00Z'),
                            metadata: { 'booking_profile_id' => world.profile.id })
  end
  let(:sent_notice) do
    Crm::MeetingNotice.create!(meeting: meeting, account: account, kind: 'booked', status: :sent, sent_at: Time.current,
                               due_at: Time.current)
  end
  let!(:pending_notice) do
    Crm::MeetingNotice.create!(meeting: meeting, account: account, kind: 'day_before', status: :pending,
                               due_at: Crm::BookingV2::Notices::Scheduler.expected_due_at(meeting, 'day_before'))
  end
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: world.contact) }
  let(:notice_message) { outgoing(conversation, crm_booking_notice: true, crm_booking_notice_id: sent_notice.id) }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true', 'FRONTEND_URL' => 'https://app.example.com') do
      travel_to(Time.zone.parse('2026-10-12T14:00:00Z')) { example.run }
    end
  end

  before do
    account.enable_features('crm_booking_v2')
    account.save!
    create_booking_invite(world: world, meeting: meeting, scheduled_at: Time.current, channel: 'public')
  end

  def outgoing(target, **attributes)
    create(:message, account: account, inbox: target.inbox, conversation: target, message_type: :outgoing, content_attributes: attributes)
  end

  def tap_reply(target: conversation, replied: notice_message, id: 'stop_notices', message_type: :incoming)
    attributes = { selected_option: { id: id, title: 'Parar avisos' } }
    attributes[:in_reply_to] = replied.id if replied
    create(:message, account: account, inbox: target.inbox, conversation: target, message_type: message_type,
                     content: 'Parar avisos', content_attributes: attributes)
  end

  def deliver(message)
    listener.message_created(Events::Base.new('message.created', Time.zone.now, message: message))
  end

  def alerts
    Crm::Activity.where(card_id: world.card.id, event_type: 'booking_notices_stopped')
  end

  def stopped?
    Crm::BookingNoticeStop.stopped?(account_id: account.id, contact_id: world.contact.id)
  end

  # Motivo: o caminho feliz. A parada vale para o contato (motivo do botão), a reunião e os avisos pendentes.
  it 'para os avisos do contato, com o motivo do botão' do
    deliver(tap_reply)

    expect(Crm::BookingNoticeStop.find_by!(account_id: account.id, contact_id: world.contact.id).reason).to eq('whatsapp_button')
    expect(meeting.reload.reminders_stopped_at).to eq(Time.current)
    expect(pending_notice.reload).to have_attributes(status: 'skipped', skip_reason: 'stopped')
  end

  # Motivo: o toque repetido (o cliente aperta duas vezes) registra a parada no card uma vez só (o "Parar avisos"
  # do `AgentAlert` só registra: não abre tarefa para o responsável).
  it 'tocar duas vezes dá um alerta só' do
    deliver(tap_reply)
    deliver(tap_reply)

    expect(alerts.count).to eq(1)
    expect(Crm::FollowUp.where(account_id: account.id)).to be_empty
  end

  # Motivo: o `selected_option` pode chegar como json em texto (o `content_attributes` é json gravado como texto).
  it 'lê o selected_option gravado como json em texto' do
    message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming,
                               content_attributes: { 'selected_option' => { 'id' => 'stop_notices' }.to_json,
                                                     'in_reply_to' => notice_message.id })

    deliver(message.reload)

    expect(stopped?).to be(true)
  end

  # Motivo: só a resposta do cliente conta; a nossa própria mensagem com a marca não para nada.
  it 'ignora mensagem de saída' do
    deliver(tap_reply(message_type: :outgoing))

    expect(stopped?).to be(false)
  end

  # Motivo: outro botão (uma opção de menu, por exemplo) não é "Parar avisos".
  it 'ignora outro id' do
    deliver(tap_reply(id: 'agendar'))

    expect(stopped?).to be(false)
  end

  # Motivo: sem a prova de que responde a um aviso nosso, nada: nem resposta solta, nem resposta a outra mensagem.
  it 'ignora resposta sem in_reply_to e in_reply_to que não é aviso' do
    deliver(tap_reply(replied: nil))
    deliver(tap_reply(replied: outgoing(conversation, crm_booking_notice: true)))
    deliver(tap_reply(replied: outgoing(conversation)))

    expect(stopped?).to be(false)
  end

  # Motivo: a mensagem respondida precisa ser da MESMA conversa (id de outra conversa não prova nada).
  it 'ignora in_reply_to de outra conversa' do
    other = create(:conversation, account: account, inbox: inbox, contact: world.contact)
    deliver(tap_reply(target: other))

    expect(stopped?).to be(false)
  end

  # Motivo: o aviso é de outro contato: quem tocou não pode parar os avisos dele.
  it 'ignora contato diferente do convite' do
    stranger = create(:contact, account: account, phone_number: '+5511900001111')
    their_conversation = create(:conversation, account: account, inbox: inbox, contact: stranger)
    marked = outgoing(their_conversation, crm_booking_notice: true, crm_booking_notice_id: sent_notice.id)

    deliver(tap_reply(target: their_conversation, replied: marked))

    expect(stopped?).to be(false)
    expect(Crm::BookingNoticeStop.where(account_id: account.id)).to be_empty
  end

  # Motivo: com o agendamento desligado na conta, o listener não age (kill-switch).
  it 'não age com a flag do agendamento desligada' do
    account.disable_features('crm_booking_v2')
    account.save!

    deliver(tap_reply)

    expect(stopped?).to be(false)
  end
end
