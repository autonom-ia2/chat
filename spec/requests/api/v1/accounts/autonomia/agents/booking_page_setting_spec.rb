require 'rails_helper'

# #1196 — a página de agendamento da agenda da IA vai e volta pela API do agente (Ajustar > Marcar reuniões). Página
# de outra conta é recusada com 422; `null` desliga.
RSpec.describe 'Autonomia agent booking page setting', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:world) { build_booking_world(account: account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Ana', agent_type: 'scheduler', instruction: 'Atenda.',
                                     config: { 'handoff_strategy' => 'none' })
  end
  let(:url) { "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}" }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true' do
      example.run
    end
  end

  def save(page_id, user: administrator, extra: {})
    patch url, params: { agent: { config: { booking_page_id: page_id }.merge(extra) } }, headers: user.create_new_auth_token, as: :json
  end

  def role_user(*permissions)
    user = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: permissions)
    user.account_users.find_by(account: account).update!(custom_role: role)
    user
  end

  it 'saves, exposes and clears the booking page' do
    save(world.profile.id)

    expect(response).to have_http_status(:success)
    expect(response.parsed_body.dig('config', 'booking_page_id')).to eq(world.profile.id)
    expect(response.parsed_body['booking_available']).to be(true)
    expect(agent.reload.config).to include('booking_page_id' => world.profile.id, 'handoff_strategy' => 'none')

    save(nil)

    expect(response).to have_http_status(:success)
    expect(agent.reload.config['booking_page_id']).to be_nil
  end

  it 'only lets people who can see Scheduling choose the page' do
    blind = role_user('autonomia_manage')

    save(world.profile.id, user: blind)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq(I18n.t('autonomia.agents.booking_page_forbidden'))
    expect(agent.reload.config).not_to have_key('booking_page_id')

    save(world.profile.id, user: role_user('autonomia_manage', 'agendamento_view'))

    expect(response).to have_http_status(:success)
    expect(agent.reload.config['booking_page_id']).to eq(world.profile.id)
  end

  it 'lets someone without Scheduling save other settings that resend the page already saved' do
    agent.update!(config: agent.config.merge('booking_page_id' => world.profile.id))

    save(world.profile.id.to_s, user: role_user('autonomia_manage'), extra: { response_window: 'always' })

    expect(response).to have_http_status(:success)
    expect(agent.reload.config).to include('booking_page_id' => world.profile.id.to_s, 'response_window' => 'always')
  end

  it 'hides the choice and refuses a page for the Quote Agent, which does not take the calendar' do
    agent.update_columns(agent_type: 'insurance_quote') # rubocop:disable Rails/SkipsModelValidations

    get url, headers: administrator.create_new_auth_token, as: :json
    expect(response.parsed_body['booking_available']).to be(false)

    save(world.profile.id)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(agent.reload.config).not_to have_key('booking_page_id')
  end

  it 'refuses a page from another account' do
    foreign = build_booking_world(account: create(:account)).profile

    save(foreign.id)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(agent.reload.config).not_to have_key('booking_page_id')
  end
end
