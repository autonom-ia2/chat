require 'rails_helper'

# Desvio do Creator para o InternalCreator (#1188): Google e Microsoft seguem iguais (RA-01).
RSpec.describe Crm::Meetings::Creator do
  let(:account) { create(:account) }
  let(:world) { build_booking_world(account: account) }
  let(:starts_at) { Time.utc(2026, 10, 20, 13, 0, 0) }
  let(:google_inbox) { create(:channel_email, account: account, provider: 'google', calendar_enabled: true).inbox }
  let(:microsoft_inbox) { create(:channel_email, :microsoft_email, account: account, calendar_enabled: true).inbox }

  before do
    travel_to Time.utc(2026, 10, 12, 11, 0, 0)
    world.contact.update!(email: 'marcos@example.com')
  end

  def schedule(inbox:, **params)
    described_class.new(account: account, card: world.card, inbox: inbox, scheduled_by: world.host, params: {
      title: 'Demo', description: 'Pauta', starts_at: starts_at, ends_at: starts_at + 30.minutes,
      timezone: 'America/Sao_Paulo', extra_guests: []
    }.merge(params)).perform
  end

  around do |example|
    with_modified_env(CRM_CALENDAR_GOOGLE_SIMULATE: 'true', CRM_CALENDAR_MS_SIMULATE: 'true') { example.run }
  end

  it 'mantém Google Meet sem local pedido e com google_meet, sem passar pelo InternalCreator' do
    allow(Crm::Meetings::InternalCreator).to receive(:new).and_call_original

    later = { starts_at: starts_at + 1.hour, ends_at: starts_at + 90.minutes }
    [schedule(inbox: google_inbox), schedule(inbox: google_inbox, location_type: 'google_meet', **later)].each do |meeting|
      expect(meeting).to have_attributes(provider: 'google', online_meeting_type: 'google_meet', status: 'scheduled', inbox_id: google_inbox.id)
      expect(meeting.external_event_id).to be_present
      expect(meeting.online_meeting_url).to start_with('https://')
      expect(meeting.meeting_guests.pluck(:email)).to eq(['marcos@example.com'])
    end
    expect(Crm::Meetings::InternalCreator).not_to have_received(:new)
  end

  it 'mantém Microsoft Teams sem local pedido e com teams' do
    later = { starts_at: starts_at + 1.hour, ends_at: starts_at + 90.minutes }
    [schedule(inbox: microsoft_inbox), schedule(inbox: microsoft_inbox, location_type: 'teams', **later)].each do |meeting|
      expect(meeting).to have_attributes(provider: 'microsoft', online_meeting_type: 'teams', status: 'scheduled')
      expect(meeting.external_event_id).to be_present
    end
  end

  it 'grava origem e metadados da página já no rascunho do Meet, e nada muda quando eles não vêm' do
    with_page = schedule(inbox: google_inbox, source: 'public_link',
                         booking_metadata: { 'booking_profile_id' => world.profile.id, 'booking_link_id' => 7 })
    plain = schedule(inbox: google_inbox, starts_at: starts_at + 1.hour, ends_at: starts_at + 90.minutes)

    expect(with_page).to have_attributes(source: 'public_link', status: 'scheduled')
    expect(with_page.metadata).to include('booking_profile_id' => world.profile.id, 'booking_link_id' => 7, 'reminder_minutes_before' => 15)
    expect(plain.source).to be_nil
    expect(plain.metadata.keys).not_to include('booking_profile_id', 'booking_link_id', 'consent')
  end

  it 'continua recusando caixa sem calendário quando não há local pedido' do
    expect { schedule(inbox: create_crm_inbox(account: account)) }.to raise_error(ArgumentError, 'unsupported_calendar_inbox')
  end

  it 'desvia local interno para reunião sem provedor, com ou sem caixa de calendário' do
    without_inbox = schedule(inbox: nil, location_type: 'whatsapp_voice', source: 'manual')
    with_inbox = schedule(inbox: google_inbox, location_type: 'in_person', starts_at: starts_at + 1.hour, ends_at: starts_at + 90.minutes)

    expect(without_inbox).to have_attributes(provider: 'internal', online_meeting_type: 'whatsapp_voice', inbox_id: nil,
                                             external_event_id: nil, source: 'manual', status: 'scheduled')
    expect(with_inbox).to have_attributes(provider: 'internal', online_meeting_type: 'in_person', inbox_id: google_inbox.id,
                                          external_event_id: nil, online_meeting_url: nil)
  end
end
