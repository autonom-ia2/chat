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
end
