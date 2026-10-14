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

  describe 'when creating the agent' do
    def create_agent(page_id, user: administrator)
      post "/api/v1/accounts/#{account.id}/autonomia/agents",
           params: { agent: { name: 'Bia', agent_type: 'scheduler', config: { booking_page_id: page_id } } },
           headers: user.create_new_auth_token, as: :json
    end

    it 'saves the page chosen by someone who can see Scheduling' do
      create_agent(world.profile.id)

      expect(response).to have_http_status(:created)
      expect(Autonomia::Agents::Agent.find(response.parsed_body['id']).config['booking_page_id']).to eq(world.profile.id)
    end

    it 'drops the computed and reserved config keys a request must never set' do
      post "/api/v1/accounts/#{account.id}/autonomia/agents",
           params: { agent: { name: 'Bia', agent_type: 'scheduler',
                              config: { handoff_strategy: 'none', topic_map: [{ topic: 'x' }], system_key: 'guide', with_knowledge: true } } },
           headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:created)
      config = Autonomia::Agents::Agent.find(response.parsed_body['id']).config
      expect(config).to include('handoff_strategy' => 'none')
      expect(config.keys).not_to include('topic_map', 'system_key', 'with_knowledge')
    end

    it 'refuses the page from someone who cannot see Scheduling and creates nothing' do
      blind = role_user('autonomia_manage')

      expect { create_agent(world.profile.id, user: blind) }.not_to change(Autonomia::Agents::Agent, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(I18n.t('autonomia.agents.booking_page_forbidden'))
    end
  end

  # #1307 — as pessoas da página que a IA pode usar. O servidor descarta id que não é pessoa da página escolhida nem da
  # mesma conta, e normaliza para inteiros únicos. Vazio = todas.
  describe 'booking_agent_ids' do
    let(:rui) { create(:user, account: account, role: :agent, name: 'Rui Prado') }
    let(:lia) { create(:user, account: account, role: :agent, name: 'Lia Souza') }
    let(:outsider) { create(:user, account: create(:account), role: :agent) }
    let(:not_on_page) { create(:user, account: account, role: :agent) }

    before do
      world.profile.update!(assignment_mode: :per_agent, default_assignee: nil)
      [rui, lia].each { |user| world.profile.agent_booking_links.create!(account: account, agent: user) }
    end

    def liberate(ids, page_id: world.profile.id, user: administrator)
      save(page_id, user: user, extra: { booking_agent_ids: ids })
    end

    it 'keeps only people of the chosen page, as unique integers, on PATCH' do
      liberate([lia.id.to_s, lia.id, outsider.id, not_on_page.id, 'x'])

      expect(response).to have_http_status(:success)
      expect(agent.reload.config['booking_agent_ids']).to eq([lia.id])
      expect(response.parsed_body.dig('config', 'booking_agent_ids')).to eq([lia.id])
    end

    it 'saves an empty list (= everyone on the page)' do
      liberate([])

      expect(response).to have_http_status(:success)
      expect(agent.reload.config['booking_agent_ids']).to eq([])
    end

    # A restrição do dono nunca vira "todas" em silêncio.
    it 'refuses a request that leaves nobody: only ids from outside the page, or a value that is not a list' do
      liberate([lia.id])

      [[outsider.id], [not_on_page.id], '1,2', ['x']].each do |pedido|
        liberate(pedido)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq(I18n.t('autonomia.agents.booking_agent_ids_invalid'))
        expect(agent.reload.config['booking_agent_ids']).to eq([lia.id])
      end
    end

    it 'a page with a single host drops ids pointing to someone else' do
      single = create_booking_profile(account: account, host: world.host, pipeline: world.pipeline, stage: world.stage)

      liberate([rui.id, world.host.id], page_id: single.id)

      expect(agent.reload.config).to include('booking_page_id' => single.id, 'booking_agent_ids' => [world.host.id])
    end

    it 'saving other settings does not touch a saved restriction, even one whose people left the page' do
      agent.update_columns(config: agent.config.merge('booking_page_id' => world.profile.id, 'booking_agent_ids' => [not_on_page.id])) # rubocop:disable Rails/SkipsModelValidations

      patch url, params: { agent: { config: { response_window: 'always' } } }, headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(agent.reload.config).to include('booking_agent_ids' => [not_on_page.id], 'response_window' => 'always')
    end

    # Trocar a página não transforma a restrição em "todas": ela fica, e a IA não vê ninguém até o dono escolher.
    it 'changing the page keeps the saved restriction, and nobody from it serves the new page' do
      liberate([lia.id])
      single = create_booking_profile(account: account, host: world.host, pipeline: world.pipeline, stage: world.stage)

      save(single.id)

      expect(response).to have_http_status(:success)
      expect(agent.reload.config).to include('booking_page_id' => single.id, 'booking_agent_ids' => [lia.id])
      with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true') do
        account.enable_features!('crm_booking_v2')
        expect(Autonomia::Agents::Tools::Native::Agenda.estado(agent.reload)).to eq('sem_responsavel')
      end
    end

    # A tela manda o config inteiro de volta: depois que a pessoa liberada sai da página, salvar outra coisa não falha.
    it 'resending a saved list whose people left the page, with other settings, passes and keeps it untouched' do
      agent.update_columns(config: agent.config.merge('booking_page_id' => world.profile.id, 'booking_agent_ids' => [not_on_page.id])) # rubocop:disable Rails/SkipsModelValidations

      liberate([not_on_page.id.to_s], user: role_user('autonomia_manage'))

      expect(response).to have_http_status(:success)
      expect(agent.reload.config['booking_agent_ids']).to eq([not_on_page.id])
    end

    it 'without Scheduling, turning a restriction whose people left into "everyone" is a change and is refused' do
      agent.update_columns(config: agent.config.merge('booking_page_id' => world.profile.id, 'booking_agent_ids' => [not_on_page.id])) # rubocop:disable Rails/SkipsModelValidations
      blind = role_user('autonomia_manage')

      liberate([], user: blind)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(agent.reload.config['booking_agent_ids']).to eq([not_on_page.id])
    end

    it 'only people who can see Scheduling change who is liberated; resending the same list is not a change' do
      liberate([lia.id])
      blind = role_user('autonomia_manage')

      liberate([rui.id], user: blind)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(agent.reload.config['booking_agent_ids']).to eq([lia.id])

      liberate([lia.id], user: blind)
      expect(response).to have_http_status(:success)
    end

    it 'validates on POST too' do
      post "/api/v1/accounts/#{account.id}/autonomia/agents",
           params: { agent: { name: 'Bia', agent_type: 'scheduler',
                              config: { booking_page_id: world.profile.id, booking_agent_ids: [rui.id, outsider.id] } } },
           headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:created)
      expect(Autonomia::Agents::Agent.find(response.parsed_body['id']).config['booking_agent_ids']).to eq([rui.id])
    end
  end

  it 'refuses a page from another account' do
    foreign = build_booking_world(account: create(:account)).profile

    save(foreign.id)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(agent.reload.config).not_to have_key('booking_page_id')
  end
end
