require 'rails_helper'

# "Enviar link para marcar outro horário" (#1193, J4-A6): cliente faltou, um toque do agente cria o link do cliente
# (InviteCreator) e o manda na conversa (InviteDeliverer), com as regras do botão Agendar. Nada sai sem o toque.
RSpec.describe Crm::BookingV2::RebookLink do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:world) { build_booking_world(account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: world.contact) }
  let(:starts_at) { Time.zone.parse('2026-10-19T13:00:00Z') }
  let(:meeting) do
    create_internal_meeting(world: world, starts_at: starts_at, conversation: conversation,
                            metadata: { 'booking_profile_id' => world.profile.id })
  end

  around do |example|
    with_modified_env('FRONTEND_URL' => 'https://app.example.com') do
      travel_to(Time.zone.parse('2026-10-19T14:00:00Z')) { example.run }
    end
  end

  def rebook(visible: ->(_conversation) { true })
    client = Crm::BookingV2::MeetingClient.new(meeting.reload, visible: visible)
    described_class.new(meeting: meeting, user: world.host, client: client).perform
  end

  def mark_no_show
    Crm::Meetings::RecordOutcomeService.new(meeting: meeting, outcome: 'no_show', actor: world.host).perform
  end

  it 'creates a new link of the meeting page for the client and sends it in the conversation as the agent' do
    mark_no_show

    invite = rebook

    expect(invite).to have_attributes(booking_profile_id: world.profile.id, contact_id: world.contact.id, card_id: world.card.id,
                                      conversation_id: conversation.id, created_by_id: world.host.id, state: 'sent')
    message = conversation.messages.last
    expect(message).to have_attributes(sender: world.host, message_type: 'outgoing', private: false)
    expect(message.content).to eq("Oi, Marcos! Escolha o melhor horário para a gente conversar: #{invite.url}")
    activity = world.card.activities.find_by(event_type: 'booking_rebook_link_sent')
    expect(activity.payload).to include('meeting_id' => meeting.id, 'invite_id' => invite.id, 'message_id' => message.id)
  end

  it 'refuses when the meeting was not marked as no-show, sending nothing' do
    expect { rebook }.to raise_error(Crm::BookingV2::MeetingActionError, 'not_rebookable')

    Crm::Meetings::RecordOutcomeService.new(meeting: meeting, outcome: 'held').perform
    expect { rebook }.to raise_error(Crm::BookingV2::MeetingActionError, 'not_rebookable')
    expect(Crm::BookingInvite.count).to eq(0)
    expect(conversation.messages.count).to eq(0)
  end

  it 'refuses a meeting that did not come from a booking page' do
    mark_no_show
    meeting.update!(metadata: {})

    expect { rebook }.to raise_error(Crm::BookingV2::MeetingActionError, 'not_rebookable')
  end

  it 'keeps the new link and returns it to copy when the window is closed or there is no conversation the person sees' do
    mark_no_show
    channel = create(:channel_api, account: account, additional_attributes: { 'agent_reply_time_window' => '12' })
    closed = create(:conversation, account: account, inbox: channel.inbox, contact: world.contact)
    meeting.update!(conversation: closed)

    expect { rebook }.to raise_error(Crm::BookingV2::MeetingActionError) do |error|
      invite = Crm::BookingInvite.last
      expect([error.message, error.url]).to eq(['cannot_reply', invite.url])
      expect(invite.sent_at).to be_nil
    end
    expect(closed.messages.count).to eq(0)

    expect { rebook(visible: ->(_conversation) { false }) }.to raise_error(Crm::BookingV2::MeetingActionError) do |error|
      expect([error.message, error.url]).to eq(['no_conversation', Crm::BookingInvite.last.url])
    end
    expect(world.card.activities.where(event_type: 'booking_rebook_link_sent')).to be_empty
  end

  it 'refuses, creating and sending nothing, when the client opted out or stopped the notices (contact or meeting)' do
    mark_no_show
    world.contact.update!(opted_out_at: Time.current)
    expect { rebook }.to raise_error(Crm::BookingV2::MeetingActionError) { |error| expect([error.message, error.url]).to eq(['stopped', nil]) }

    world.contact.update!(opted_out_at: nil)
    Crm::BookingNoticeStop.create!(account: account, contact: world.contact)
    expect { rebook }.to raise_error(Crm::BookingV2::MeetingActionError, 'stopped')

    Crm::BookingNoticeStop.delete_all
    meeting.update!(reminders_stopped_at: Time.current)
    expect { rebook }.to raise_error(Crm::BookingV2::MeetingActionError, 'stopped')

    expect(Crm::BookingInvite.count).to eq(0)
    expect(conversation.messages.count).to eq(0)
  end

  it 'refuses a second tap within 10 minutes without a new link, and allows it after that' do
    mark_no_show
    first = rebook
    expect(meeting.reload.metadata).to include('rebook_link_sent_at' => Time.current.iso8601, 'rebook_link_sent_by_id' => world.host.id)

    expect { rebook }.to raise_error(Crm::BookingV2::MeetingActionError) { |error| expect([error.message, error.url]).to eq(['recently_sent', nil]) }
    expect(Crm::BookingInvite.count).to eq(1)
    expect(conversation.messages.count).to eq(1)

    # Depois da espera sai de novo, com o mesmo link ainda válido (o InviteCreator reaproveita o convite aberto).
    travel 11.minutes
    expect(rebook.id).to eq(first.id)
    expect(conversation.messages.count).to eq(2)
  end

  it 'sees, under the lock, a send made after the meeting was loaded (two taps at once)' do
    mark_no_show
    stale = Crm::Meeting.find(meeting.id)
    rebook

    client = Crm::BookingV2::MeetingClient.new(stale, visible: ->(_conversation) { true })
    expect { described_class.new(meeting: stale, user: world.host, client: client).perform }
      .to raise_error(Crm::BookingV2::MeetingActionError, 'recently_sent')
    expect(conversation.messages.count).to eq(1)
  end

  it 'does not start the wait when the message could not go out' do
    mark_no_show
    expect { rebook(visible: ->(_conversation) { false }) }.to raise_error(Crm::BookingV2::MeetingActionError, 'no_conversation')

    expect(meeting.reload.metadata).not_to have_key('rebook_link_sent_at')
    expect { rebook }.to change(conversation.messages, :count).by(1)
  end

  it 'falls back to the page the person attends when the meeting page was paused' do
    mark_no_show
    other = create_booking_profile(account: account, host: world.host, pipeline: world.pipeline, stage: world.stage, title: 'Outra')
    world.profile.update!(enabled: false)

    expect(rebook.booking_profile_id).to eq(other.id)
  end

  it 'refuses with no_page when no page receives links anymore' do
    mark_no_show
    world.profile.update!(enabled: false)

    expect { rebook }.to raise_error(Crm::BookingV2::InviteError, 'no_page')
    expect(conversation.messages.count).to eq(0)
  end
end
