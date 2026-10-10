require 'rails_helper'

RSpec.describe Crm::Meetings::InternalCreator do
  let(:account) { create(:account) }
  let(:world) { build_booking_world(account: account) }
  let(:starts_at) { Time.utc(2026, 10, 20, 13, 0, 0) }

  before { travel_to Time.utc(2026, 10, 12, 11, 0, 0) }

  def create_meeting(inbox: nil, **params)
    described_class.new(account: account, card: world.card, inbox: inbox, scheduled_by: world.host, params: {
      title: 'Conversa <b>de</b> 30 min', description: '<script>x</script>Olá', starts_at: starts_at, ends_at: starts_at + 30.minutes,
      timezone: 'America/Sao_Paulo', extra_guests: [], location_type: 'whatsapp_video', source: 'public_link'
    }.merge(params)).perform
  end

  it 'cria reunião interna agendada, sem provedor, com convidado só de telefone' do
    meeting = create_meeting

    expect(meeting).to have_attributes(provider: 'internal', status: 'scheduled', online_meeting_type: 'whatsapp_video',
                                       inbox_id: nil, external_event_id: nil, online_meeting_url: nil, source: 'public_link',
                                       title: 'Conversa <b>de</b> 30 min', description: 'Olá')
    guest = meeting.meeting_guests.sole
    expect(guest).to have_attributes(email: nil, phone_number: '+5511912345678', contact_id: world.contact.id, guest_type: 'contact_guest')
    expect(meeting.metadata).to include('reminder_minutes_before' => 15, 'location' => { 'type' => 'whatsapp_video' })
  end

  it 'cria o lembrete do agente, atualiza o próximo vencimento do card e registra a atividade' do
    meeting = create_meeting

    reminder = meeting.reminder
    expect(reminder).to have_attributes(follow_up_type: 'meeting', status: 'pending', due_at: starts_at - 15.minutes,
                                        assignee_id: world.host.id, card_id: world.card.id)
    expect(reminder.metadata).to include('meeting_id' => meeting.id, 'source' => 'crm_meeting')
    expect(world.card.reload.next_follow_up_at).to eq(reminder.due_at)
    activity = Crm::Activity.where(card_id: world.card.id, event_type: 'meeting_scheduled').sole
    expect(activity.payload).to include('meeting_id' => meeting.id, 'provider' => 'internal', 'location_type' => 'whatsapp_video')
  end

  it 'usa o link do perfil para custom_link e recusa link que não é web' do
    meeting = create_meeting(location_type: 'custom_link', location_url: 'https://zoom.us/j/123')
    expect(meeting).to have_attributes(online_meeting_type: 'custom_link', online_meeting_url: 'https://zoom.us/j/123')

    expect { create_meeting(location_type: 'custom_link', location_url: 'javascript:alert(1)', starts_at: starts_at + 1.day) }
      .to raise_error(ActiveRecord::RecordInvalid, /http or https/)
  end

  it 'grava presencial com endereço, consentimento e página de origem' do
    consent = { accepted_at: '2026-10-12T08:00:00-03:00', text_key: 'booking.consent.v1' }
    meeting = create_meeting(location_type: 'in_person', location_address: 'Rua A, 10', booking_profile_id: world.profile.id, consent: consent)

    expect(meeting.online_meeting_type).to eq('in_person')
    expect(meeting.metadata).to include('location' => { 'type' => 'in_person', 'address' => 'Rua A, 10' },
                                        'booking_profile_id' => world.profile.id,
                                        'consent' => { 'accepted_at' => '2026-10-12T08:00:00-03:00', 'text_key' => 'booking.consent.v1' })
  end

  it 'junta e-mail do contato, telefone digitado e e-mail extra sem repetir' do
    world.contact.update!(email: 'marcos@example.com')

    meeting = create_meeting(guest_phone: '+5521987654321', extra_guests: ['MARCOS@example.com', 'socio@example.com'])

    expect(meeting.meeting_guests.order(:id).pluck(:email, :phone_number, :guest_type))
      .to eq([['marcos@example.com', '+5521987654321', 'contact_guest'], ['socio@example.com', nil, 'external_email']])
  end

  it 'recusa local que não é interno e cliente sem como ser alcançado' do
    expect { create_meeting(location_type: 'google_meet') }.to raise_error(ArgumentError, 'invalid_location')

    world.contact.update!(phone_number: nil)
    expect { create_meeting }.to raise_error(ArgumentError, 'no_reachable_guest')
    expect(account.crm_meetings.count).to eq(0)
  end

  it 'invalida a disponibilidade só quando há caixa' do
    inbox = create(:channel_email, account: account, provider: 'google', calendar_enabled: true).inbox
    allow(Crm::Meetings::AvailabilityService).to receive(:invalidate)

    create_meeting
    expect(Crm::Meetings::AvailabilityService).not_to have_received(:invalidate)

    create_meeting(inbox: inbox, starts_at: starts_at + 1.day, ends_at: starts_at + 1.day + 30.minutes)
    expect(Crm::Meetings::AvailabilityService).to have_received(:invalidate)
      .with(inbox_id: inbox.id, date: '2026-10-21', timezone: 'America/Sao_Paulo').once
  end
end
