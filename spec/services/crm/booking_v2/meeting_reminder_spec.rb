require 'rails_helper'

# "Lembrar" (#1193, J4-A5): só com o toque do agente, uma mensagem curta na conversa com o link de gestão pedindo
# para confirmar. Respeita a janela do canal, a parada de avisos e não repete em 10 minutos.
RSpec.describe Crm::BookingV2::MeetingReminder do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:world) { build_booking_world(account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: world.contact) }
  let(:starts_at) { Time.zone.parse('2026-10-20T13:00:00Z') }
  let(:meeting) do
    create_internal_meeting(world: world, starts_at: starts_at, conversation: conversation,
                            metadata: { 'booking_profile_id' => world.profile.id })
  end
  let!(:invite) do
    create_booking_invite(world: world, conversation: conversation, meeting: meeting, scheduled_at: 1.day.ago, channel: 'conversation')
  end

  around do |example|
    with_modified_env('FRONTEND_URL' => 'https://app.example.com') do
      travel_to(Time.zone.parse('2026-10-19T14:00:00Z')) { example.run }
    end
  end

  def remind(user: world.host, visible: ->(_conversation) { true })
    client = Crm::BookingV2::MeetingClient.new(meeting.reload, visible: visible)
    described_class.new(meeting: meeting, user: user, client: client).perform
  end

  def refusal
    remind
    nil
  rescue Crm::BookingV2::MeetingActionError => e
    [e.message, e.url]
  end

  it 'sends a short message from the agent with the manage link and records the reminder on the meeting and card' do
    message = remind

    expect(message).to have_attributes(conversation_id: conversation.id, sender: world.host, message_type: 'outgoing', private: false)
    expect(message.content).to eq("Oi, Marcos! Passando para lembrar do seu horário em 20/10 às 10:00. Pode confirmar por aqui? #{invite.url}")
    expect(message.content_attributes['crm_booking_invite_id']).to eq(invite.id)
    expect(meeting.reload.metadata).to include('reminded_at' => Time.current.iso8601, 'reminded_by_id' => world.host.id)
    activity = world.card.activities.find_by(event_type: 'booking_agent_reminded')
    expect(activity.payload).to include('meeting_id' => meeting.id, 'message_id' => message.id, 'by' => 'agent',
                                        'starts_at' => starts_at.iso8601)
    expect(activity.actor_id).to eq(world.host.id)
  end

  it 'refuses a meeting that did not come from a booking page, is not scheduled or already started' do
    meeting.update!(metadata: {})
    expect(refusal).to eq(['not_remindable', nil])

    meeting.update!(metadata: { 'booking_profile_id' => world.profile.id }, status: :canceled)
    expect(refusal).to eq(['not_remindable', nil])

    meeting.update!(status: :scheduled, starts_at: 1.minute.ago, ends_at: 29.minutes.from_now)
    expect(refusal).to eq(['not_remindable', nil])
    expect(conversation.messages.count).to eq(0)
  end

  it 'refuses when the client already confirmed' do
    meeting.update!(confirmation_status: :confirmed, confirmed_at: Time.current)

    expect(refusal).to eq(['already_confirmed', nil])
    expect(conversation.messages.count).to eq(0)
  end

  it 'refuses, with no link to copy, when the client opted out or stopped the notices (contact or meeting)' do
    world.contact.update!(opted_out_at: Time.current)
    expect(refusal).to eq(['stopped', nil])

    world.contact.update!(opted_out_at: nil)
    Crm::BookingNoticeStop.create!(account: account, contact: world.contact)
    expect(refusal).to eq(['stopped', nil])

    Crm::BookingNoticeStop.delete_all
    meeting.update!(reminders_stopped_at: Time.current)
    expect(refusal).to eq(['stopped', nil])
    expect(conversation.messages.count).to eq(0)
  end

  it 'refuses without a usable manage link' do
    invite.update!(canceled_at: Time.current)

    expect(refusal).to eq(['no_invite', nil])
  end

  it 'refuses a second tap within 10 minutes and allows it after that' do
    remind
    expect(refusal).to eq(['recently_reminded', nil])

    travel 11.minutes
    expect { remind }.to change(conversation.messages, :count).by(1)
  end

  it 'refuses with the link to copy when the channel window is closed' do
    channel = create(:channel_api, account: account, additional_attributes: { 'agent_reply_time_window' => '12' })
    closed = create(:conversation, account: account, inbox: channel.inbox, contact: world.contact)
    meeting.update!(conversation: closed)
    invite.update!(conversation: closed)

    expect(refusal).to eq(['cannot_reply', invite.url])
    expect(closed.messages.count).to eq(0)
    expect(meeting.reload.metadata).not_to have_key('reminded_at')
  end

  it 'refuses with the link to copy when the person cannot see any conversation of the client' do
    client = Crm::BookingV2::MeetingClient.new(meeting, visible: ->(_conversation) { false })

    expect { described_class.new(meeting: meeting, user: world.host, client: client).perform }
      .to raise_error(Crm::BookingV2::MeetingActionError) { |error| expect([error.message, error.url]).to eq(['no_conversation', invite.url]) }
    expect(conversation.messages.count).to eq(0)
  end
end
