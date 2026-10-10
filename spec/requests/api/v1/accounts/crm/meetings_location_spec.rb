require 'rails_helper'

# O JSON da reunião passa a dizer onde ela acontece (#1188): `location_type` e `location` (rótulo e endereço), sem
# tirar nenhum campo antigo.
RSpec.describe 'Api::V1::Accounts::Crm::Meetings location', type: :request do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let(:world) { build_booking_world(account: account) }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true') { example.run }
  end

  def fetch(meeting)
    get "/api/v1/accounts/#{account.id}/crm/meetings/#{meeting.id}", headers: admin.create_new_auth_token, as: :json
    response.parsed_body['payload']
  end

  it 'devolve tipo, rótulo e endereço do local presencial' do
    meeting = create_internal_meeting(
      world: world, starts_at: 2.days.from_now, online_meeting_type: :in_person,
      metadata: { 'location' => { 'type' => 'in_person', 'label' => 'Loja Centro', 'address' => 'Rua A, 10' } }
    )

    payload = fetch(meeting)

    expect(response).to have_http_status(:ok)
    expect(payload).to include('location_type' => 'in_person', 'online_meeting_type' => 'in_person',
                               'location' => { 'label' => 'Loja Centro', 'address' => 'Rua A, 10' })
    expect(payload.keys).to include('provider', 'online_meeting_url', 'guests', 'scheduled_by')
  end

  # J6-A4 (#1196): a reunião marcada pela IA é identificável no card.
  it 'devolve a origem da reunião' do
    expect(fetch(create_internal_meeting(world: world, starts_at: 2.days.from_now, source: 'ai'))).to include('source' => 'ai')
  end

  it 'devolve rótulo e endereço vazios quando a reunião não tem local gravado' do
    payload = fetch(create_internal_meeting(world: world, starts_at: 2.days.from_now))

    expect(payload).to include('location_type' => 'whatsapp_video', 'location' => { 'label' => nil, 'address' => nil })
  end

  # #1192: resposta do cliente e avisos no WhatsApp, para o card e o calendário (F2-B).
  it 'devolve a confirmação do cliente, se ele parou os avisos e os avisos em ordem' do
    meeting = create_internal_meeting(world: world, starts_at: 2.days.from_now, confirmation_status: :confirmed,
                                      reminders_stopped_at: Time.current)
    hour = Crm::MeetingNotice.create!(meeting: meeting, account: account, kind: 'hour_before', due_at: meeting.starts_at - 1.hour,
                                      status: :skipped, skip_reason: 'stopped')
    booked = Crm::MeetingNotice.create!(meeting: meeting, account: account, kind: 'booked', due_at: 1.hour.ago, status: :sent)

    payload = fetch(meeting)

    expect(payload).to include(
      'booking' => false, 'confirmation_status' => 'confirmed', 'notices_stopped' => true,
      'notices' => [
        { 'kind' => 'booked', 'due_at' => booked.due_at.iso8601, 'status' => 'sent', 'skip_reason' => nil },
        { 'kind' => 'hour_before', 'due_at' => hour.due_at.iso8601, 'status' => 'skipped', 'skip_reason' => 'stopped' }
      ]
    )
  end

  it 'marca booking verdadeiro na reunião que veio de uma página de agendamento' do
    meeting = create_internal_meeting(world: world, starts_at: 2.days.from_now, metadata: { 'booking_profile_id' => world.profile.id })

    expect(fetch(meeting)).to include('booking' => true, 'confirmation_status' => 'pending', 'notices_stopped' => false)
  end
end
