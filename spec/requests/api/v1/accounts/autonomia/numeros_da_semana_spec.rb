require 'rails_helper'

# #1181 (L1) — números da semana de todos os agentes numa chamada só, atrás da flag autonomia_agents_journey.
# "Respondidas" = conversas distintas com resposta do agente (evento replied). "Passadas para a equipe" =
# conversas distintas com handoff, na mesma regra do outcome handed_off do Desempenho.
RSpec.describe 'Autonomia numeros da semana', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:path) { "/api/v1/accounts/#{account.id}/autonomia/numeros_da_semana" }

  around do |example|
    with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run }
  end

  before { account.enable_features!('autonomia_agents_journey') }

  def create_agent(name, owner: account, config: {})
    Autonomia::Agents::Agent.create!(account: owner, name: name, agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda.', config: config)
  end

  def conversation_in(owner = account, owner_inbox = inbox)
    create(:conversation, account: owner, inbox: owner_inbox)
  end

  def event(agent, conversation, type, at: Time.current)
    Autonomia::Agents::AgentEvent.create!(agent: agent, account: agent.account, conversation_id: conversation.id,
                                          event_type: type, created_at: at)
  end

  def core_handoff(conversation, at: Time.current)
    create(:reporting_event, account: conversation.account, inbox: conversation.inbox, conversation: conversation,
                             name: 'conversation_bot_handoff', event_start_time: at, event_end_time: at)
  end

  def get_numeros(params: {}, user: administrator)
    get path, params: params, headers: user.create_new_auth_token, as: :json
  end

  def row_for(agent)
    response.parsed_body['payload'].find { |row| row['agent_id'] == agent.id }
  end

  describe 'gates' do
    it 'responds 404 when the account does not have the journey flag' do
      account.disable_features!('autonomia_agents_journey')

      get_numeros

      expect(response).to have_http_status(:not_found)
    end

    it 'responds 404 when the Agents module is off for the account' do
      with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'false') { get_numeros }

      expect(response).to have_http_status(:not_found)
    end

    it 'keeps plain agents without a role out' do
      get_numeros(user: create(:user, account: account, role: :agent))

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET numeros_da_semana' do
    let!(:bia) { create_agent('Bia') }

    it 'answers with the 7-day window of the Desempenho tab and one row per agent' do
      quieto = create_agent('Quieto')

      get_numeros

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['range']).to eq('7d')
      expect(Time.zone.parse(body['from'])).to eq(6.days.ago.beginning_of_day)
      expect(Time.zone.parse(body['to'])).to be_within(1.minute).of(Time.current)
      expect(body['payload']).to eq([
                                      { 'agent_id' => bia.id, 'answered' => 0, 'handed' => 0 },
                                      { 'agent_id' => quieto.id, 'answered' => 0, 'handed' => 0 }
                                    ])
    end

    it 'counts distinct conversations answered and handed to the team inside the window' do
      respondida = conversation_in
      event(bia, respondida, :replied)
      event(bia, respondida, :replied)
      event(bia, conversation_in, :replied)
      event(bia, conversation_in, :handed_off)
      event(bia, conversation_in, :skipped_audience)
      event(bia, conversation_in, :skipped_schedule)
      event(bia, conversation_in, :skipped_escolhas_incompletas)
      event(bia, conversation_in, :replied, at: 8.days.ago)
      assumida = conversation_in
      event(bia, assumida, :replied)
      core_handoff(assumida)

      get_numeros

      expect(row_for(bia)).to eq('agent_id' => bia.id, 'answered' => 3, 'handed' => 4)
    end

    it 'matches the handed_off outcome of the Desempenho tab' do
      event(bia, conversation_in, :handed_off)
      event(bia, conversation_in, :skipped_schedule)
      assumida = conversation_in
      event(bia, assumida, :replied)
      core_handoff(assumida)
      antiga = conversation_in
      event(bia, antiga, :replied)
      core_handoff(antiga, at: 10.days.ago)
      event(bia, conversation_in, :handed_off, at: 9.days.ago)

      get_numeros

      desempenho = Autonomia::Agents::Analytics.new(agent: bia, range: '7d').outcomes
      expect(row_for(bia)['handed']).to eq(desempenho[:handed_off])
      expect(row_for(bia)['handed']).to eq(3)
    end

    it 'does not count a core handoff of a conversation the agent did not touch this week' do
      alheia = conversation_in
      event(bia, alheia, :replied, at: 9.days.ago)
      core_handoff(alheia)

      get_numeros

      expect(row_for(bia)).to include('answered' => 0, 'handed' => 0)
    end

    it 'leaves system and deleted agents out' do
      guia = create_agent('Guia', config: { 'system_key' => 'platform_guide' })
      apagado = create_agent('Apagado')
      Autonomia::Agents::SoftDelete.new(agent: apagado, actor: administrator).perform

      get_numeros

      expect(response.parsed_body['payload'].pluck('agent_id')).to eq([bia.id])
      expect(response.parsed_body['payload'].pluck('agent_id')).not_to include(guia.id, apagado.id)
    end

    it 'filters by agent_id' do
      outro = create_agent('Outro')
      event(outro, conversation_in, :replied)

      get_numeros(params: { agent_id: outro.id })

      expect(response.parsed_body['payload']).to eq([{ 'agent_id' => outro.id, 'answered' => 1, 'handed' => 0 }])
    end

    context 'with another account' do
      let(:other_account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
      let(:other_inbox) { create(:inbox, account: other_account) }
      let!(:alheio) { create_agent('Alheio', owner: other_account) }

      before do
        conversa = conversation_in(other_account, other_inbox)
        event(alheio, conversa, :replied)
        core_handoff(conversa)
      end

      it 'never shows agents or numbers of another account' do
        get_numeros

        expect(response.parsed_body['payload']).to eq([{ 'agent_id' => bia.id, 'answered' => 0, 'handed' => 0 }])
      end

      it 'responds 404 for an agent_id of another account' do
        get_numeros(params: { agent_id: alheio.id })

        expect(response).to have_http_status(:not_found)
      end
    end

    it 'runs the same number of queries for one agent and for five agents (no N+1)' do
      count_queries = lambda do
        queries = 0
        counter = ->(*, payload) { queries += 1 unless payload[:name] == 'SCHEMA' || payload[:cached] }
        ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') { get_numeros }
        queries
      end

      event(bia, conversation_in, :replied)
      get_numeros # aquece caches de primeira requisição, que não dependem do número de agentes
      com_um = count_queries.call
      4.times do |index|
        agent = create_agent("Agente #{index}")
        event(agent, conversation_in, :handed_off)
        event(agent, conversation_in, :replied)
      end
      com_cinco = count_queries.call

      expect(response.parsed_body['payload'].size).to eq(5)
      expect(com_cinco).to eq(com_um)
    end
  end
end
