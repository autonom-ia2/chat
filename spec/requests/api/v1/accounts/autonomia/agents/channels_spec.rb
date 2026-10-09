require 'rails_helper'

RSpec.describe 'Autonomia agent channels projection', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:other_account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) { create_agent(account: account, name: 'Agente consultado') }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true' do
      example.run
    end
  end

  def create_agent(account:, name:, attrs: {})
    Autonomia::Agents::Agent.create!(
      { account: account, name: name, agent_type: 'custom', mode: :guided,
        status: :active, enabled: true, actuation: :external, instruction: 'Atenda.' }.merge(attrs)
    )
  end

  def create_native_link(agent:, inbox:, deleted_at: nil)
    mirror = AgentBot.create!(account: agent.account, name: agent.name, bot_type: :webhook, outgoing_url: nil)
    link = Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox,
                                                 account: agent.account, agent_bot: mirror)
    AgentBotInbox.create!(inbox: inbox, agent_bot: mirror, account: agent.account) unless deleted_at
    link.update!(deleted_at: deleted_at, updated_at: deleted_at) if deleted_at
    link
  end

  def list_channels
    get "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}/channels",
        headers: administrator.create_new_auth_token,
        as: :json
  end

  it 'returns kept links, eligible inboxes and occupancy scoped to the current account', :aggregate_failures do
    connected_inbox = create(:inbox, account: account, name: 'WhatsApp ligado', working_hours_enabled: true)
    eligible_inbox = create(:inbox, account: account, name: 'Site elegível', working_hours_enabled: true)
    archived_inbox = create(:inbox, account: account, name: 'Vínculo arquivado')
    other_agent_inbox = create(:inbox, account: account, name: 'Ocupada por outro agente')
    external_bot_inbox = create(:inbox, account: account, name: 'Ocupada por bot externo')
    foreign_inbox = create(:inbox, account: other_account, name: 'Outra conta')

    create(:crm_service_schedule, account: account, owner: connected_inbox,
                                  weekdays: [1, 2, 3, 4, 5], hours: [['09:00', '18:00']])
    create_native_link(agent: agent, inbox: connected_inbox)
    archived_link = create_native_link(agent: agent, inbox: archived_inbox, deleted_at: Time.current)

    other_agent = create_agent(account: account, name: 'Outro agente')
    create_native_link(agent: other_agent, inbox: other_agent_inbox)

    external_bot = AgentBot.create!(account: account, name: 'Bot privado', outgoing_url: 'https://bot.example')
    AgentBotInbox.create!(inbox: external_bot_inbox, agent_bot: external_bot, account: account)

    foreign_agent = create_agent(account: other_account, name: 'Agente de outra conta')
    create_native_link(agent: foreign_agent, inbox: foreign_inbox)

    list_channels

    expect(response).to have_http_status(:success)
    body = response.parsed_body
    payload_ids = body.fetch('payload').pluck('inbox_id')
    eligible_ids = body.fetch('eligible_inboxes').pluck('id')
    occupied = body.fetch('occupied_inboxes').index_by { |entry| entry.fetch('id') }

    expect(payload_ids).to contain_exactly(connected_inbox.id)
    expect(eligible_ids).to include(eligible_inbox.id, archived_inbox.id)
    expect(eligible_ids).not_to include(connected_inbox.id, other_agent_inbox.id, external_bot_inbox.id, foreign_inbox.id)
    expect(occupied.fetch(other_agent_inbox.id).fetch('occupied_by')).to include(
      'kind' => 'agent', 'agent_id' => other_agent.id, 'agent_name' => other_agent.name
    )
    expect(occupied.fetch(external_bot_inbox.id).fetch('occupied_by')).to eq('kind' => 'other_bot')
    expect(occupied.fetch(external_bot_inbox.id).fetch('occupied_by')).not_to have_key('agent_name')

    connected = body.fetch('payload').find { |entry| entry['inbox_id'] == connected_inbox.id }
    eligible = body.fetch('eligible_inboxes').find { |entry| entry['id'] == eligible_inbox.id }
    expect(connected['has_schedule']).to be(true)
    expect(eligible['has_schedule']).to be(true)
    expect(archived_link.reload.deleted_at).to be_present
    expect(Autonomia::Agents::AgentInbox.find_by!(inbox_id: foreign_inbox.id).autonomia_agent_id).to eq(foreign_agent.id)
  end

  it 'uses inbox working hours when no usable service schedule exists' do
    working_hours_inbox = create(:inbox, account: account, name: 'Horário da caixa', working_hours_enabled: true)
    list_channels

    expect(response).to have_http_status(:success)
    entry = response.parsed_body.fetch('eligible_inboxes').find { |inbox| inbox['id'] == working_hours_inbox.id }
    expect(entry['has_schedule']).to be(true)
  end

  it 'does not treat an enabled schedule without usable blocks as a schedule' do
    inbox = create(:inbox, account: account, name: 'Sem horário utilizável')
    Crm::ServiceSchedule.create!(account: account, owner: inbox, timezone: 'America/Sao_Paulo', enabled: false,
                                 blocks: [{ 'day_of_week' => 1, 'start_minute' => 540, 'end_minute' => 1080 }])

    list_channels

    expect(response).to have_http_status(:success)
    entry = response.parsed_body.fetch('eligible_inboxes').find { |candidate| candidate['id'] == inbox.id }
    expect(entry['has_schedule']).to be(false)
  end
end
