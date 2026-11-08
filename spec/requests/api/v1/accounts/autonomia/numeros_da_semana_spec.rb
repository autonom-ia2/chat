require 'rails_helper'

# #1181 (L1) — números da semana de todos os agentes numa chamada só, atrás da flag autonomia_agents_journey.
# #2000: a conta é a única da IA (Autonomia::ContaDaIa), a mesma da linha da IA em CRM › Números › Equipe.
# "Respondidas" = conversas com resposta do espelho do agente; "Passadas" = conversas que o agente passou para alguém da
# equipe (Crm::Passagem); "Resolvidas" = resolvidas na semana, com resposta dele e sem ninguém da equipe no meio.
# E cada cartão tem o tamanho da lista que ele abre (analytics/conversations).
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
    agent = Autonomia::Agents::Agent.create!(account: owner, name: name, agent_type: 'custom', status: :active, enabled: true,
                                             instruction: 'Atenda.', config: config)
    Autonomia::Agents::AgentInbox.create!(agent: agent, inbox: create(:inbox, account: owner), account: owner,
                                          agent_bot: create(:agent_bot, account: owner))
    agent
  end

  def espelho(agent)
    Autonomia::Agents::AgentInbox.find_by!(autonomia_agent_id: agent.id).agent_bot
  end

  def conversation_in(owner = account, owner_inbox = inbox)
    create(:conversation, account: owner, inbox: owner_inbox)
  end

  def resposta(agent, conversation, at: Time.current)
    create(:message, account: conversation.account, inbox: conversation.inbox, conversation: conversation,
                     message_type: :outgoing, sender: espelho(agent), created_at: at)
  end

  def passagem(agent, conversation, at: Time.current)
    Crm::Passagem.create!(account: conversation.account, conversation: conversation, de_type: 'Autonomia::Agents::Agent',
                          de_id: agent.id, de_nome: agent.name, para_type: 'User', para_id: administrator.id,
                          para_nome: administrator.name, motivo: 'robo_pediu', em: at)
  end

  def resolvida(conversation, at: Time.current)
    create(:reporting_event, account: conversation.account, inbox: conversation.inbox, conversation: conversation,
                             name: 'conversation_resolved', event_start_time: at, event_end_time: at)
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

    it 'answers with the 7-day window and one row per agent' do
      quieto = create_agent('Quieto')

      get_numeros

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['range']).to eq('7d')
      expect(Time.zone.parse(body['from'])).to eq(Autonomia::ContaDaIa.semana(account).begin)
      expect(Time.zone.parse(body['to'])).to be_within(1.minute).of(Time.current)
      expect(body['payload']).to eq([
                                      { 'agent_id' => bia.id, 'answered' => 0, 'handed' => 0, 'resolved' => 0 },
                                      { 'agent_id' => quieto.id, 'answered' => 0, 'handed' => 0, 'resolved' => 0 }
                                    ])
    end

    it 'counts distinct conversations, never repeated events, inside the week' do
      duas_vezes = conversation_in
      resposta(bia, duas_vezes)
      resposta(bia, duas_vezes)
      passagem(bia, duas_vezes)
      passagem(bia, duas_vezes)
      por_horario = conversation_in
      passagem(bia, por_horario)
      sozinha = conversation_in
      resposta(bia, sozinha)
      resolvida(sozinha)
      antiga = conversation_in
      resposta(bia, antiga, at: 8.days.ago)
      passagem(bia, antiga, at: 8.days.ago)

      get_numeros

      expect(row_for(bia)).to eq('agent_id' => bia.id, 'answered' => 2, 'handed' => 2, 'resolved' => 1)
    end

    it 'does not count as solved alone a conversation someone from the team stepped into' do
      [conversation_in, conversation_in, conversation_in].each { |chat| resposta(bia, chat) && resolvida(chat) }
      passada, assumida, respondida = Conversation.where(account_id: account.id).order(:id).last(3)
      passagem(bia, passada, at: 9.days.ago)
      core_handoff(assumida, at: 9.days.ago)
      create(:message, account: account, inbox: inbox, conversation: respondida, message_type: :outgoing, sender: administrator)

      get_numeros

      expect(row_for(bia)).to include('answered' => 3, 'resolved' => 0)
    end

    it 'does not count the private handoff note as an answer: answered 0, handed 1' do
      chat = conversation_in
      create(:message, account: account, inbox: chat.inbox, conversation: chat, message_type: :outgoing, sender: espelho(bia),
                       private: true)
      passagem(bia, chat)

      get_numeros

      expect(row_for(bia)).to eq('agent_id' => bia.id, 'answered' => 0, 'handed' => 1, 'resolved' => 0)
    end

    it 'counts each agent by its own mirror and its own handoffs' do
      outro = create_agent('Outro')
      conversa = conversation_in
      resposta(bia, conversa)
      resposta(outro, conversa)
      passagem(outro, conversa)

      get_numeros

      expect(row_for(bia)).to include('answered' => 1, 'handed' => 0)
      expect(row_for(outro)).to include('answered' => 1, 'handed' => 1)
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
      resposta(outro, conversation_in)

      get_numeros(params: { agent_id: outro.id })

      expect(response.parsed_body['payload']).to eq([{ 'agent_id' => outro.id, 'answered' => 1, 'handed' => 0, 'resolved' => 0 }])
    end

    context 'with another account' do
      let(:other_account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
      let(:other_inbox) { create(:inbox, account: other_account) }
      let!(:alheio) { create_agent('Alheio', owner: other_account) }

      before do
        conversa = conversation_in(other_account, other_inbox)
        resposta(alheio, conversa)
        Crm::Passagem.create!(account: other_account, conversation: conversa, de_type: 'Autonomia::Agents::Agent', de_id: bia.id,
                              para_type: 'User', para_id: administrator.id, motivo: 'robo_pediu', em: Time.current)
      end

      it 'never shows agents or numbers of another account' do
        get_numeros

        expect(response.parsed_body['payload']).to eq([{ 'agent_id' => bia.id, 'answered' => 0, 'handed' => 0, 'resolved' => 0 }])
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

      resposta(bia, conversation_in)
      get_numeros # aquece caches de primeira requisição, que não dependem do número de agentes
      com_um = count_queries.call
      4.times do |index|
        agent = create_agent("Agente #{index}")
        passagem(agent, conversation_in)
        resposta(agent, conversation_in)
      end
      com_cinco = count_queries.call

      expect(response.parsed_body['payload'].size).to eq(5)
      expect(com_cinco).to eq(com_um)
    end
  end

  # #2000, critério de pronto: o cartão tem o tamanho da lista que ele abre (mesmo agente, mesma semana, mesmo universo).
  describe 'card equals the list it opens' do
    let!(:bia) { create_agent('Bia') }

    def lista(metric)
      get "/api/v1/accounts/#{account.id}/autonomia/agents/#{bia.id}/analytics/conversations",
          params: { range: '7d', metric: metric }, headers: administrator.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      response.parsed_body['payload'].map { |row| row.dig('conversation', 'id') }
    end

    before do
      duas_vezes = conversation_in
      resposta(bia, duas_vezes)
      resposta(bia, duas_vezes)
      # Passada por horário: o agente não respondeu. Não é "respondida", e antes entrava na lista do cartão.
      passagem(bia, conversation_in)
      sozinha = conversation_in
      resposta(bia, sozinha)
      resolvida(sozinha)
      resposta(bia, conversation_in, at: 8.days.ago)
    end

    it 'has the same answered, handed and solved conversations in the card and in the list' do
      get_numeros(params: { agent_id: bia.id })
      cartao = row_for(bia)

      respondidas = lista('respondidas')
      passadas = lista('passadas')
      resolvidas = lista('resolvidas_sozinha')

      expect(cartao).to include('answered' => 2, 'handed' => 1, 'resolved' => 1)
      expect(respondidas.size).to eq(cartao['answered'])
      expect(respondidas.uniq.size).to eq(respondidas.size)
      expect(passadas.size).to eq(cartao['handed'])
      expect(resolvidas.size).to eq(cartao['resolved'])
    end
  end
end
