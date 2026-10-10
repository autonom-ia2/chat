require 'rails_helper'

# Calendário do CRM (#1192): cada reunião diz se veio de uma página de agendamento, a resposta do cliente e se ele
# parou os avisos, para o selo do popover.
RSpec.describe 'CRM calendar booking fields', type: :request do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let(:world) { build_booking_world(account: account) }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true') { example.run }
  end

  def meeting_events
    get "/api/v1/accounts/#{account.id}/crm/calendar/events",
        params: { from: 1.hour.ago.iso8601, to: 5.days.from_now.iso8601 }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    response.parsed_body['payload'].select { |event| event['event_type'] == 'meeting' }.index_by { |event| event['id'] }
  end

  it 'devolve booking, confirmation_status e notices_stopped de cada reunião' do
    booked = create_internal_meeting(world: world, starts_at: 2.days.from_now, confirmation_status: :confirmed,
                                     reminders_stopped_at: Time.current, metadata: { 'booking_profile_id' => world.profile.id })
    manual = create_internal_meeting(world: world, starts_at: 3.days.from_now)

    events = meeting_events

    expect(events["meeting_#{booked.id}"]).to include('booking' => true, 'confirmation_status' => 'confirmed', 'notices_stopped' => true)
    expect(events["meeting_#{manual.id}"]).to include('booking' => false, 'confirmation_status' => 'pending', 'notices_stopped' => false)
  end
end
