require 'rails_helper'

# Passar reuniões (#1195, J8-A10) por HTTP: quem pode, prévia sem gravar com o mesmo formato da passagem, conflitos,
# página de outra conta e pessoa que não pode atender.
RSpec.describe 'Api::V1::Accounts::Crm::BookingPages reassign', type: :request do
  let(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator, name: 'Admin Ana') }
  let(:world) { build_booking_world(account: account) }
  let(:to) { create(:user, account: account, role: :agent, name: 'Rui Prado') }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/booking_pages" }
  let(:tuesday) { ActiveSupport::TimeZone['America/Sao_Paulo'].parse('2026-10-20 10:00') }

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

  def page_meeting(host, starts_at)
    create_internal_meeting(world: world, starts_at: starts_at, created_by: host, metadata: { 'booking_profile_id' => world.profile.id })
  end

  def params_for(**extra)
    { from_user_id: world.host.id, to_user_id: to.id }.merge(extra)
  end

  def preview(user, **extra)
    get "#{base}/reassign_preview", params: params_for(**extra), headers: user.create_new_auth_token
  end

  def reassign(user, **extra)
    post "#{base}/reassign", params: params_for(**extra), headers: user.create_new_auth_token, as: :json
  end

  it 'deixa só administrador e agendamento_manage; os demais recebem 401 e nada muda' do
    meeting = page_meeting(world.host, tuesday)
    denied = { view: role_user('agendamento_view'), agent: create(:user, account: account, role: :agent),
               crm_only: role_user('crm_view', 'crm_admin') }

    denied.each do |who, user|
      preview(user)
      expect(response).to have_http_status(:unauthorized), "#{who} preview: #{response.status}"
      reassign(user)
      expect(response).to have_http_status(:unauthorized), "#{who} reassign: #{response.status}"
    end
    expect(meeting.reload.created_by_id).to eq(world.host.id)

    preview(role_user('agendamento_manage'))
    expect(response).to have_http_status(:ok)
  end

  it 'a prévia mostra o mesmo resultado da passagem, sem gravar' do
    free = page_meeting(world.host, tuesday)
    busy = page_meeting(world.host, tuesday + 1.hour)
    page_meeting(to, tuesday + 1.hour)
    expected = { 'moved' => 1, 'conflicts' => [{ 'meeting_id' => busy.id, 'starts_at' => busy.starts_at.iso8601, 'title' => busy.title }] }

    preview(admin, page_id: world.profile.id)

    expect(response.parsed_body).to eq('payload' => expected)
    expect(free.reload.created_by_id).to eq(world.host.id)

    reassign(admin, page_id: world.profile.id)

    expect(response.parsed_body).to eq('payload' => expected)
    expect(free.reload.created_by_id).to eq(to.id)
    expect(busy.reload.created_by_id).to eq(world.host.id)
  end

  it 'recusa pessoa que não pode atender (422) e página de outra conta (404)' do
    page_meeting(world.host, tuesday)
    no_crm = role_user('agendamento_manage')

    reassign(admin, to_user_id: no_crm.id)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error' => 'crm.booking_v2.people_invalid')

    other_account = create(:account)
    other_page = create_booking_profile(account: other_account, host: create(:user, account: other_account))
    reassign(admin, page_id: other_page.id)
    expect(response).to have_http_status(:not_found)
    expect(Crm::Meeting.where(created_by_id: to.id)).to be_empty
  end

  it 'responde 404 com a flag da conta desligada' do
    account.disable_features('crm_booking_v2')
    account.save!

    reassign(admin)

    expect(response).to have_http_status(:not_found)
  end
end
