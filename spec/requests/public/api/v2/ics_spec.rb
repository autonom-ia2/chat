require 'rails_helper'

# "Salvar na minha agenda" (#1189, J2-A11): token no caminho, arquivo de calendário sem e-mail, 404 uniforme.
RSpec.describe 'Public::Api::V2::Ics', type: :request do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:world) { build_booking_world(account: account) }
  let(:meeting) { create_internal_meeting(world: world, starts_at: Time.zone.parse('2026-10-20T13:00:00Z')) }
  let(:invite) { create_booking_invite(world: world, meeting: meeting, scheduled_at: Time.current) }
  let(:token) { Crm::BookingV2::Tokens.generate('ics', { 'c' => invite.code }, expires_in: 2.days) }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true') { example.run }
  end

  before do
    travel_to Time.utc(2026, 10, 12, 11, 0, 0)
    account.enable_features('crm_booking_v2')
    account.save!
    world.host.update!(email: 'camila.host@example.com')
    world.contact.update!(email: 'marcos@example.com')
  end

  def expect_not_found
    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body).to eq({ 'error' => 'not_found' })
  end

  it 'entrega o arquivo de calendário com o local em texto leigo e sem e-mail' do
    get "/public/api/v2/ics/#{token}"

    expect(response).to have_http_status(:ok)
    expect(response.headers['Content-Type']).to eq('text/calendar; charset=utf-8')
    expect(response.headers['Content-Disposition']).to start_with('attachment; filename="reuniao.ics"')
    expect(response.body).to start_with("BEGIN:VCALENDAR\r\n")
    expect(response.body).to include("UID:meeting-#{meeting.id}@", "DTSTART:20261020T130000Z\r\n", "DTEND:20261020T133000Z\r\n",
                                     "SUMMARY:Conversa de 30 min\r\n", "LOCATION:Vídeo no WhatsApp\r\n", "STATUS:CONFIRMED\r\n")
    %w[camila.host@example.com marcos@example.com +5511912345678 ORGANIZER ATTENDEE].each { |text| expect(response.body).not_to include(text) }
  end

  it 'responde 404 uniforme para token inválido, de outro propósito, vencido, sem reunião ou com a flag desligada' do
    form = Crm::BookingV2::Tokens.generate('form', { 'c' => invite.code }, expires_in: 2.days)
    open_invite = create_booking_invite(world: world)
    without_meeting = Crm::BookingV2::Tokens.generate('ics', { 'c' => open_invite.code }, expires_in: 2.days)
    ['lixo', form, without_meeting].each do |bad|
      get "/public/api/v2/ics/#{bad}"
      expect_not_found
    end

    valid = token
    account.disable_features('crm_booking_v2')
    account.save!
    get "/public/api/v2/ics/#{valid}"
    expect_not_found

    account.enable_features('crm_booking_v2')
    account.save!
    travel 2.days + 1.minute
    get "/public/api/v2/ics/#{valid}"
    expect_not_found
  end
end
