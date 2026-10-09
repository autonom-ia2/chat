require 'rails_helper'

# Gestão da reunião pelo link do convite (#1192, contrato F2-A): payload `meeting` exato, confirmar, cancelar,
# remarcar, parar avisos, 422 com código público, cancelada aberta até 1 dia depois do fim e 404 uniforme (J5-A2).
RSpec.describe 'Public::Api::V2::Invites manage', type: :request do
  let(:frontend) { 'https://app.example.com' }
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:world) { build_booking_world(account: account) }
  let(:starts_at) { Time.utc(2026, 10, 20, 13, 0, 0) }
  let(:meeting) { create_internal_meeting(world: world, starts_at: starts_at, metadata: { 'booking_profile_id' => world.profile.id }) }
  let(:invite) { create_booking_invite(world: world, meeting: meeting, scheduled_at: Time.current, channel: 'public') }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true', 'FRONTEND_URL' => frontend) { example.run }
  end

  before do
    travel_to Time.utc(2026, 10, 12, 14, 0, 0)
    account.enable_features('crm_booking_v2')
    account.save!
    world.host.update!(display_name: 'Camila')
    world.profile.update!(contact_phone: '+5511933334444')
  end

  def show(code = invite.code)
    get "/public/api/v2/invites/#{code}"
  end

  def act(action, code = invite.code, **params)
    post "/public/api/v2/invites/#{code}/#{action}", params: params, as: :json
  end

  def body
    response.parsed_body
  end

  def expect_error(code)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(body).to eq('error' => code)
  end

  it 'GET devolve a reunião exatamente como no contrato, sem id, e-mail ou telefone' do
    show

    expect(response).to have_http_status(:ok)
    expect(body.except('meeting')).to eq(
      'code' => invite.code, 'page_slug' => world.profile.slug, 'state' => 'scheduled', 'contact_first_name' => 'Marcos',
      'phone_masked' => '(11) •••••-5678', 'contact_whatsapp_url' => 'https://wa.me/5511933334444',
      'starts_at' => '2026-10-20T10:00:00-03:00', 'timezone' => 'America/Sao_Paulo'
    )
    expect(body['meeting'].except('ics_url')).to eq(
      'starts_at' => '2026-10-20T10:00:00-03:00', 'ends_at' => '2026-10-20T10:30:00-03:00', 'timezone' => 'America/Sao_Paulo',
      'title' => 'Conversa de 30 min', 'agent_name' => 'Camila',
      'location' => { 'type' => 'whatsapp_video', 'label' => 'Vídeo no WhatsApp', 'join_url' => nil, 'address' => nil },
      'status' => 'scheduled', 'confirmation_status' => 'pending', 'can_change' => true,
      'change_deadline' => '2026-10-20T08:00:00-03:00', 'notices_stopped' => false
    )
    expect(body['meeting']['ics_url']).to start_with("#{frontend}/public/api/v2/ics/")
    [meeting.id, invite.id, account.id, world.contact.id].each { |id| expect(response.body).not_to include("\"#{id}\"") }
    expect(response.body).not_to include('+5511912345678')
  end

  it 'convite ainda não agendado não tem meeting nem ações' do
    open_invite = create_booking_invite(world: world)

    show(open_invite.code)
    expect(body.keys).to contain_exactly('code', 'page_slug', 'state', 'contact_first_name', 'phone_masked')

    act(:confirm, open_invite.code)
    expect_error('not_changeable')
  end

  it 'confirm responde o mesmo JSON do GET, já confirmado, e confirmar de novo não avisa de novo (J5-A6)' do
    act(:confirm)
    act(:confirm)

    expect(response).to have_http_status(:ok)
    expect(body['meeting']['confirmation_status']).to eq('confirmed')
    expect(Crm::FollowUp.where("metadata->>'event' = ?", 'confirmed').count).to eq(1)
  end

  it 'cancel cancela e a página continua abrindo como Cancelada até 1 dia depois do fim, depois 404 uniforme' do
    act(:cancel)

    expect(response).to have_http_status(:ok)
    expect(body['meeting']).to include('status' => 'canceled', 'can_change' => false)
    expect(meeting.reload.status).to eq('canceled')

    act(:cancel)
    expect_error('not_changeable')

    travel_to(meeting.ends_at + 1.day - 1.minute) { show }
    expect(body['meeting']['status']).to eq('canceled')

    travel_to(meeting.ends_at + 1.day + 1.minute) { show }
    expect(response).to have_http_status(:not_found)
    expect(body).to eq('error' => 'not_found')
  end

  it 'cancel e reschedule fora do prazo respondem too_late e a tela mostra can_change falso' do
    meeting.update_columns(starts_at: 90.minutes.from_now, ends_at: 120.minutes.from_now) # rubocop:disable Rails/SkipsModelValidations

    act(:cancel)
    expect_error('too_late')
    act(:reschedule, starts_at: '2026-10-21T11:00:00-03:00')
    expect_error('too_late')

    show
    expect(body['meeting']['can_change']).to be(false)
  end

  it 'reschedule move a reunião; horário ocupado responde slot_unavailable' do
    act(:reschedule, starts_at: '2026-10-21T11:00:00-03:00')

    expect(response).to have_http_status(:ok)
    expect(body['meeting']).to include('starts_at' => '2026-10-21T11:00:00-03:00', 'confirmation_status' => 'pending')

    create_internal_meeting(world: world, starts_at: Time.utc(2026, 10, 22, 14, 0, 0))
    act(:reschedule, starts_at: '2026-10-22T11:00:00-03:00')
    expect_error('slot_unavailable')
  end

  it 'stop_notices registra a parada e a reunião continua marcada (J5-A7)' do
    act(:stop_notices)

    expect(response).to have_http_status(:ok)
    expect(body['meeting']).to include('notices_stopped' => true, 'status' => 'scheduled')
    expect(Crm::BookingNoticeStop.where(account_id: account.id, contact_id: world.contact.id).count).to eq(1)
  end

  it 'link de gestão continua valendo com a página pausada (o cliente ainda pode cancelar)' do
    world.profile.update!(enabled: false)

    act(:cancel)

    expect(response).to have_http_status(:ok)
    expect(meeting.reload.status).to eq('canceled')
  end

  it 'código inexistente, convite cancelado e flag desligada: 404 uniforme em toda ação' do
    canceled = create_booking_invite(world: world, meeting: meeting, scheduled_at: Time.current, canceled_at: Time.current)

    actions = %i[confirm cancel reschedule stop_notices]
    [['nao_existe'], [canceled.code]].each do |(code)|
      actions.each do |action|
        act(action, code)
        expect(response).to have_http_status(:not_found), "#{code} #{action}"
        expect(body).to eq('error' => 'not_found')
      end
    end

    account.disable_features('crm_booking_v2')
    account.save!
    act(:confirm)
    expect(response).to have_http_status(:not_found)
    expect(meeting.reload.confirmation_status).to eq('pending')
  end
end
