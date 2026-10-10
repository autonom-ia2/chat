require 'rails_helper'

# #1181 (L2) — canais da conta e quem atende cada um: um agente nativo (com nome) ou um atendimento
# automático externo (sem nome). Atrás da flag autonomia_agents_journey.
RSpec.describe 'Autonomia canais ocupados', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:path) { "/api/v1/accounts/#{account.id}/autonomia/canais_ocupados" }

  around do |example|
    with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run }
  end

  before { account.enable_features!('autonomia_agents_journey') }

  def create_agent(name, status: :active, enabled: true, config: {})
    Autonomia::Agents::Agent.create!(account: account, name: name, agent_type: 'support', status: status, enabled: enabled,
                                     config: config)
  end

  # Mesmo desenho do InboxConnector: vínculo nativo + AgentBot espelho (sem outgoing_url) na caixa.
  def link_native(agent, inbox)
    mirror = create(:agent_bot, account: account, outgoing_url: nil)
    AgentBotInbox.create!(inbox: inbox, agent_bot: mirror)
    Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: inbox, account: account, agent_bot: mirror)
  end

  def link_webhook(inbox)
    AgentBotInbox.create!(inbox: inbox, agent_bot: create(:agent_bot, account: account))
  end

  def get_canais(user: administrator)
    get path, headers: user.create_new_auth_token, as: :json
  end

  def occupied_by(inbox)
    response.parsed_body['payload'].find { |row| row['inbox_id'] == inbox.id }['occupied_by']
  end

  describe 'gates' do
    it 'responds 404 when the account does not have the journey flag' do
      account.disable_features!('autonomia_agents_journey')

      get_canais

      expect(response).to have_http_status(:not_found)
    end

    it 'responds 404 when the Agents module is off for the account' do
      with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'false') { get_canais }

      expect(response).to have_http_status(:not_found)
    end

    it 'keeps plain agents without a role out' do
      get_canais(user: create(:user, account: account, role: :agent))

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET canais_ocupados' do
    it 'lists every inbox of the account by name with its channel type' do
      zeta = create(:inbox, account: account, name: 'Zeta')
      alfa = create(:inbox, account: account, name: 'Alfa')

      get_canais

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload']).to eq([
                                                      { 'inbox_id' => alfa.id, 'name' => 'Alfa',
                                                        'channel_type' => alfa.channel_type, 'occupied_by' => nil },
                                                      { 'inbox_id' => zeta.id, 'name' => 'Zeta',
                                                        'channel_type' => zeta.channel_type, 'occupied_by' => nil }
                                                    ])
    end

    it 'names the native agent that answers an inbox and whether it is answering now' do
      atendendo = create(:inbox, account: account)
      parado = create(:inbox, account: account)
      bia = create_agent('Bia')
      leo = create_agent('Leo', status: :paused)
      link_native(bia, atendendo)
      link_native(leo, parado)

      get_canais

      expect(occupied_by(atendendo)).to eq('kind' => 'agent', 'agent_id' => bia.id, 'agent_name' => 'Bia', 'operating' => true)
      expect(occupied_by(parado)).to eq('kind' => 'agent', 'agent_id' => leo.id, 'agent_name' => 'Leo', 'operating' => false)
    end

    it 'treats a disabled agent as not answering' do
      inbox = create(:inbox, account: account)
      link_native(create_agent('Desligado', enabled: false), inbox)

      get_canais

      expect(occupied_by(inbox)).to include('kind' => 'agent', 'operating' => false)
    end

    it 'marks an inbox held by an external webhook bot as external, without a name' do
      inbox = create(:inbox, account: account)
      link_webhook(inbox)

      get_canais

      expect(occupied_by(inbox)).to eq('kind' => 'external')
    end

    it 'still sees the external bot when its agent_bot_inboxes row has no account_id' do
      inbox = create(:inbox, account: account)
      link_webhook(inbox).update_column(:account_id, nil) # rubocop:disable Rails/SkipsModelValidations

      get_canais

      expect(occupied_by(inbox)).to eq('kind' => 'external')
    end

    it 'frees the inbox of a deleted agent' do
      inbox = create(:inbox, account: account)
      apagado = create_agent('Apagado')
      link_native(apagado, inbox)
      Autonomia::Agents::SoftDelete.new(agent: apagado, actor: administrator).perform

      get_canais

      expect(occupied_by(inbox)).to be_nil
    end

    it 'never names a system agent: its inbox shows as external' do
      inbox = create(:inbox, account: account)
      link_native(create_agent('Guia', config: { 'system_key' => 'platform_guide' }), inbox)

      get_canais

      expect(occupied_by(inbox)).to eq('kind' => 'external')
    end

    it 'never shows inboxes or agents of another account' do
      mine = create(:inbox, account: account)
      other_account = create(:account, internal_attributes: { 'autonomia_agents_enabled' => true })
      other_inbox = create(:inbox, account: other_account)
      AgentBotInbox.create!(inbox: other_inbox, agent_bot: create(:agent_bot, account: other_account))

      get_canais

      expect(response.parsed_body['payload'].pluck('inbox_id')).to eq([mine.id])
    end

    it 'runs the same number of queries for one inbox and for five inboxes (no N+1)' do
      count_queries = lambda do
        queries = 0
        counter = ->(*, payload) { queries += 1 unless payload[:name] == 'SCHEMA' || payload[:cached] }
        ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') { get_canais }
        queries
      end

      link_native(create_agent('Primeiro'), create(:inbox, account: account))
      get_canais # aquece caches de primeira requisição, que não dependem do número de caixas
      com_uma = count_queries.call
      2.times { |index| link_native(create_agent("Agente #{index}"), create(:inbox, account: account)) }
      link_webhook(create(:inbox, account: account))
      create(:inbox, account: account)
      com_cinco = count_queries.call

      expect(response.parsed_body['payload'].size).to eq(5)
      expect(com_cinco).to eq(com_uma)
    end
  end
end
