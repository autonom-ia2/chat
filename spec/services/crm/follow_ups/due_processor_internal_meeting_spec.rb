require 'rails_helper'

# Lembrete ao agente de reunião da página de agendamento nova (#1193, J4-A4): a reunião interna não tem caixa de
# calendário, e o lembrete de 15 minutos antes continua indo por push e e-mail, como nas reuniões do Google/Microsoft.
RSpec.describe Crm::FollowUps::DueProcessor do
  let(:account) { create(:account) }
  let(:world) { build_booking_world(account: account) }
  let(:starts_at) { Time.utc(2026, 10, 20, 13, 0, 0) }
  let(:meeting) do
    Crm::Meetings::InternalCreator.new(account: account, card: world.card, inbox: nil, scheduled_by: world.host, params: {
                                         title: 'Conversa de 30 min', starts_at: starts_at, ends_at: starts_at + 30.minutes,
                                         timezone: 'America/Sao_Paulo', extra_guests: [], location_type: 'whatsapp_video',
                                         source: 'public_link', booking_profile_id: world.profile.id
                                       }).perform
  end

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'FRONTEND_URL' => 'https://app.example.com', 'SMTP_ADDRESS' => 'smtp.example.com') do
      travel_to(Time.utc(2026, 10, 12, 11, 0, 0)) { example.run }
    end
  end

  before do
    world.host.update!(confirmed_at: Time.current)
    world.host.notification_settings.find_by(account_id: account.id)
         .update!(email_crm_followup_reminder: true, push_crm_followup_reminder: true)
    create(:notification_subscription, user: world.host, subscription_attributes: { endpoint: 'https://push.example', p256dh: 'p', auth: 'a' })
    allow(VapidService).to receive_messages(public_key: 'public', private_key: 'private')
    allow(WebPush).to receive(:payload_send)
  end

  it 'sends the push and the e-mail 15 minutes before, with no calendar mailbox' do
    expect(meeting).to have_attributes(inbox_id: nil, provider: 'internal')
    reminder = meeting.reminder
    expect(reminder).to have_attributes(inbox_id: nil, due_at: starts_at - 15.minutes, assignee_id: world.host.id)

    travel_to(reminder.due_at + 1.second)
    expect { described_class.new.perform }
      .to have_enqueued_job(ActionMailer::MailDeliveryJob).with('Crm::FollowUpReminderMailer', 'reminder', 'deliver_now', anything)

    expect(reminder.reload.status).to eq('overdue')
    expect(WebPush).to have_received(:payload_send).once do |args|
      message = JSON.parse(args[:message])
      expect(message).to include('meeting_id' => meeting.id, 'meeting_title' => 'Conversa de 30 min', 'online_meeting_type' => 'whatsapp_video')
      expect(message['title']).to include('Conversa de 30 min')
    end
  end

  it 'renders the reminder e-mail of an internal meeting without a join button' do
    mail = Crm::FollowUpReminderMailer.with(account: account).reminder(meeting.reminder, world.host)

    expect(mail.to).to eq([world.host.email])
    expect(mail.subject).to include('Conversa de 30 min')
    body = mail.body.decoded
    expect(body).to include('Conversa de 30 min')
    expect(body).not_to include('Join meeting')
  end
end
