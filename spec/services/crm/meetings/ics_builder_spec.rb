require 'rails_helper'

RSpec.describe Crm::Meetings::IcsBuilder do
  let(:account) { create(:account) }
  let(:world) { build_booking_world(account: account) }
  let(:starts_at) { Time.utc(2026, 10, 20, 13, 0, 0) }
  let(:meeting) do
    location = { 'type' => 'in_person', 'address' => 'Rua A, 10; sala 2' }
    create_internal_meeting(world: world, starts_at: starts_at, title: 'Reunião; café, ação 🚀',
                            description: "Linha 1\nLinha 2 com \\ barra", metadata: { 'location' => location })
  end

  before { travel_to Time.utc(2026, 10, 12, 11, 0, 0) }

  def build(**)
    described_class.new(meeting: meeting, uid_host: 'chat.example.com', **).build
  end

  def unfolded(ics)
    ics.gsub("\r\n ", '')
  end

  it 'monta um evento importável, sem METHOD, ORGANIZER, ATTENDEE nem e-mail' do
    world.contact.update!(email: 'marcos@example.com')
    ics = build

    expect(ics).to start_with("BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:")
    expect(ics).to end_with("END:VEVENT\r\nEND:VCALENDAR\r\n")
    expect(ics).not_to include('METHOD', 'ORGANIZER', 'ATTENDEE', 'mailto:', '@example.com')
    lines = unfolded(ics).split("\r\n")
    expect(lines).to include("UID:meeting-#{meeting.id}@chat.example.com", 'SEQUENCE:0', 'DTSTAMP:20261012T110000Z',
                             'DTSTART:20261020T130000Z', 'DTEND:20261020T133000Z', 'STATUS:CONFIRMED')
  end

  it 'escapa ponto-e-vírgula, vírgula, barra e quebra de linha e mantém acento e emoji' do
    lines = unfolded(build).split("\r\n")

    expect(lines).to include('SUMMARY:Reunião\\; café\\, ação 🚀', 'DESCRIPTION:Linha 1\\nLinha 2 com \\\\ barra',
                             'LOCATION:Rua A\\, 10\\; sala 2')
  end

  it 'dobra linha longa em 75 octetos sem partir caractere UTF-8' do
    meeting.update!(title: "Consultoria #{'çãé🚀' * 30}")
    raw_lines = build.split("\r\n")

    expect(raw_lines).to all(satisfy { |line| line.bytesize <= 75 && line.valid_encoding? })
    summary = raw_lines.drop_while { |line| !line.start_with?('SUMMARY:') }
    expect(summary[1]).to start_with(' ')
    expect(unfolded(build)).to include("SUMMARY:Consultoria #{'çãé🚀' * 30}\r\n")
  end

  it 'põe URL só quando é http ou https e marca reunião cancelada' do
    meeting.update!(online_meeting_type: :custom_link, online_meeting_url: 'https://meet.example.com/abc')
    expect(unfolded(build)).to include("URL:https://meet.example.com/abc\r\n")

    meeting.assign_attributes(online_meeting_url: 'javascript:alert(1)', status: :canceled)
    meeting.save!(validate: false)
    ics = build
    expect(ics).not_to include('URL:')
    expect(ics).to include("STATUS:CANCELLED\r\n")
  end

  it 'usa o rótulo quando não há endereço e o SEQUENCE informado' do
    meeting.update!(metadata: { 'location' => { 'type' => 'whatsapp_video' } })

    ics = build(location_label: 'Chamada de vídeo no WhatsApp', sequence: 3)

    expect(ics).to include("LOCATION:Chamada de vídeo no WhatsApp\r\n", "SEQUENCE:3\r\n")
  end
end
