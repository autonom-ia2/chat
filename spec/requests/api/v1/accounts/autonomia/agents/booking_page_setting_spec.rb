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

  def save(page_id)
    patch url, params: { agent: { config: { booking_page_id: page_id } } }, headers: administrator.create_new_auth_token, as: :json
  end

  it 'saves, exposes and clears the booking page' do
    save(world.profile.id)

    expect(response).to have_http_status(:success)
    expect(response.parsed_body.dig('config', 'booking_page_id')).to eq(world.profile.id)
    expect(agent.reload.config).to include('booking_page_id' => world.profile.id, 'handoff_strategy' => 'none')

    save(nil)

    expect(response).to have_http_status(:success)
    expect(agent.reload.config['booking_page_id']).to be_nil
  end

  it 'refuses a page from another account' do
    foreign = build_booking_world(account: create(:account)).profile

    save(foreign.id)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(agent.reload.config).not_to have_key('booking_page_id')
  end
end
