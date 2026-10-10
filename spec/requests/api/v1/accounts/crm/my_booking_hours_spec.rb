require 'rails_helper'

# Meus horários (#1195, J8-A11) por HTTP: a pessoa vê e ajusta só os próprios dias e horas, dentro dos limites das
# páginas em que atende, e pausa a própria agenda, sem precisar de agendamento_manage.
RSpec.describe 'Api::V1::Accounts::Crm::MyBookingHours', type: :request do
  let(:account) { create(:account) }
  let(:world) { build_booking_world(account: account) }
  let(:agent) { world.host }
  let(:path) { "/api/v1/accounts/#{account.id}/crm/my_booking_hours" }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true') { example.run }
  end

  before do
    travel_to Time.utc(2026, 10, 12, 11, 0, 0)
    account.enable_features('crm_booking_v2')
    account.save!
  end

  def role_user(*permissions)
    user = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: permissions)
    user.account_users.find_by(account: account).update!(custom_role: role)
    user
  end

  def put_hours(user, body)
    put path, params: body, headers: user.create_new_auth_token, as: :json
  end

  def payload
    response.parsed_body['payload']
  end

  it 'mostra o horário da página como ponto de partida, com os limites e as páginas' do
    get path, headers: agent.create_new_auth_token

    expect(response).to have_http_status(:ok)
    expect(payload).to eq(
      'paused' => false, 'custom_hours' => false, 'weekdays' => [1, 2, 3, 4, 5], 'start_hour' => 9, 'end_hour' => 17,
      'limits' => { 'weekdays' => [1, 2, 3, 4, 5], 'start_hour' => 9, 'end_hour' => 17 },
      'pages' => [{ 'id' => world.profile.id, 'title' => world.profile.title }]
    )
  end

  it 'o agente comum (sem função) ajusta os próprios dias e horas dentro da página, e só os dele' do
    colleague = create(:user, account: account, role: :agent)

    put_hours(agent, working_hours: { start_hour: 10, end_hour: 16, weekdays: [1, 2, 3, 5] })

    expect(response).to have_http_status(:ok)
    expect(payload).to include('custom_hours' => true, 'weekdays' => [1, 2, 3, 5], 'start_hour' => 10, 'end_hour' => 16)
    expect(Crm::AgentAvailability.where(account: account).pluck(:user_id, :working_hours)).to eq(
      [[agent.id, { 'start_hour' => 10, 'end_hour' => 16, 'weekdays' => [1, 2, 3, 5] }]]
    )
    expect(Crm::AgentAvailability.where(user_id: colleague.id)).to be_empty
  end

  it 'não amplia além da página: dia ou hora de fora volta 422 e nada é gravado' do
    [
      { start_hour: 8, end_hour: 16, weekdays: [1] },
      { start_hour: 9, end_hour: 18, weekdays: [1] },
      { start_hour: 9, end_hour: 17, weekdays: [1, 6] }
    ].each do |hours|
      put_hours(agent, working_hours: hours)
      expect(response).to have_http_status(:unprocessable_entity), hours.inspect
      expect(response.parsed_body).to eq('error' => 'crm.booking_v2.my_hours_outside_page')
    end
    expect(Crm::AgentAvailability.count).to eq(0)
  end

  it 'recusa horas sem sentido com 422' do
    put_hours(agent, working_hours: { start_hour: 15, end_hour: 10, weekdays: [1] })

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('crm.booking_v2.my_hours_invalid')
    expect(Crm::AgentAvailability.count).to eq(0)
  end

  it 'pausa e volta a agenda, e volta a seguir a página' do
    put_hours(agent, working_hours: { start_hour: 10, end_hour: 12, weekdays: [2] })
    put_hours(agent, paused: true)
    expect(payload).to include('paused' => true, 'custom_hours' => true, 'start_hour' => 10)
    expect(Crm::BookingV2::Slots.next_slot(profile: world.profile, host: agent)).to be_nil

    put_hours(agent, paused: false, use_page_hours: true)
    expect(payload).to include('paused' => false, 'custom_hours' => false, 'start_hour' => 9, 'end_hour' => 17)
    expect(Crm::BookingV2::Slots.next_slot(profile: world.profile, host: agent)).to be_present
  end

  it 'quem não atende em página nenhuma pode pausar, mas não ajustar horas' do
    admin = create(:user, account: account, role: :administrator)

    get path, headers: admin.create_new_auth_token
    expect(payload).to include('limits' => nil, 'pages' => [])

    put_hours(admin, working_hours: { start_hour: 9, end_hour: 12, weekdays: [1] })
    expect(response.parsed_body).to eq('error' => 'crm.booking_v2.my_hours_no_pages')

    put_hours(admin, paused: true)
    expect(response).to have_http_status(:ok)
  end

  it 'conta as páginas em que a pessoa atende por link individual' do
    seller = create(:user, account: account, role: :agent)
    team_page = create_booking_profile(account: account, host: agent, pipeline: world.pipeline, stage: world.stage,
                                       working_hours: { 'start_hour' => 7, 'end_hour' => 12, 'weekdays' => [6] })
    Crm::BookingV2::PagePeople.new(team_page).assign!([agent.id, seller.id])

    get path, headers: seller.create_new_auth_token

    expect(payload['limits']).to eq('weekdays' => [6], 'start_hour' => 7, 'end_hour' => 12)
    expect(payload['pages']).to eq([{ 'id' => team_page.id, 'title' => team_page.title }])
  end

  it 'função sem CRM recebe 401 mesmo com agendamento_manage; função com crm_view entra' do
    no_crm = role_user('agendamento_manage', 'agendamento_view')

    get path, headers: no_crm.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
    put_hours(no_crm, paused: true)
    expect(response).to have_http_status(:unauthorized)
    expect(Crm::AgentAvailability.count).to eq(0)

    get path, headers: role_user('crm_view').create_new_auth_token
    expect(response).to have_http_status(:ok)
  end

  it 'responde 404 com a flag da conta desligada' do
    account.disable_features('crm_booking_v2')
    account.save!

    get path, headers: agent.create_new_auth_token

    expect(response).to have_http_status(:not_found)
  end
end
