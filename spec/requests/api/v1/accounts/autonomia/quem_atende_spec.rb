require 'rails_helper'

# chat#1648 — a aba "Agente de IA" da caixa lê quem atende ali (agente da plataforma ou de outro sistema), quem atende
# primeiro e as opções da troca. Sem flag (jornada ou Fase 2) e com a autorização da tela de configuração da caixa.
RSpec.describe 'Autonomia quem_atende API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:url) { "/api/v1/accounts/#{account.id}/autonomia/inboxes/#{inbox.id}/quem_atende" }

  def vincular!(nome, papel, caixa: inbox)
    agente = Autonomia::Agents::Agent.create!(account: account, name: nome, agent_type: 'custom', status: :active, enabled: true)
    espelho = create(:agent_bot, account: account, name: nome, outgoing_url: nil)
    Autonomia::Agents::AgentInbox.create!(agent: agente, inbox: caixa, account: account, agent_bot: espelho, papel: papel)
  end

  def ler(user = admin)
    get url, headers: user.create_new_auth_token, as: :json
    response.parsed_body
  end

  def agentes(user = admin)
    ler(user)['agentes']
  end

  def plataforma(agente, papel)
    { 'tipo' => 'plataforma', 'id' => agente.id, 'name' => agente.name, 'papel' => papel, 'avatar_url' => nil }
  end

  it 'lists the porta first and then the areas by name, only kept links' do
    vincular!('Zeca', 'area')
    porta = vincular!('Clara', 'porta')
    vincular!('Ana', 'area')
    vincular!('Velho', 'area').update!(deleted_at: Time.current)
    vincular!('De outra caixa', 'porta', caixa: create(:inbox, account: account))

    expect(agentes).to eq([
                            plataforma(porta.agent, 'porta'),
                            plataforma(Autonomia::Agents::Agent.find_by(name: 'Ana'), 'area'),
                            plataforma(Autonomia::Agents::Agent.find_by(name: 'Zeca'), 'area')
                          ])
    expect(response.parsed_body['primeiro']).to eq('tipo' => 'plataforma', 'id' => porta.autonomia_agent_id, 'name' => 'Clara')
    expect(response).to have_http_status(:ok)
  end

  it 'reads the agent from another system that answers first, never a mirror of a platform agent' do
    bot = create(:agent_bot, account: account, name: 'Automação', outgoing_url: 'https://automacao.example.com/hook')
    AgentBotInbox.create!(inbox: inbox, agent_bot: bot, account: account)

    leitura = ler

    expect(leitura['agentes']).to eq([{ 'tipo' => 'webhook', 'id' => bot.id, 'name' => 'Automação', 'papel' => 'porta',
                                        'avatar_url' => nil }])
    expect(leitura['primeiro']).to eq('tipo' => 'webhook', 'id' => bot.id, 'name' => 'Automação')
  end

  describe 'opcoes' do
    let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }

    around do |example|
      with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run }
    end

    def agente(nome, **attrs)
      Autonomia::Agents::Agent.create!({ account: account, name: nome, agent_type: 'custom', status: :paused, enabled: false }.merge(attrs))
    end

    it 'offers the agents that can answer customers and the agents from another system, by name, with the refusal reason' do
      porta = vincular!('Sofia', 'porta')
      bia = vincular!('Bia', 'area').agent
      leo = agente('Leo')
      agente('Copiloto', actuation: :internal, status: :active, enabled: true)
      agente('Rascunho', status: :draft)
      bot = create(:agent_bot, account: account, name: 'Automação', outgoing_url: 'https://automacao.example.com/hook')
      create(:agent_bot, account: create(:account), name: 'Alheio')

      opcoes = ler['opcoes']

      expect(opcoes).to eq([
                             { 'tipo' => 'webhook', 'id' => bot.id, 'name' => 'Automação', 'recusa' => nil },
                             { 'tipo' => 'plataforma', 'id' => bia.id, 'name' => 'Bia', 'recusa' => 'agente_ja_e_da_equipe' },
                             { 'tipo' => 'plataforma', 'id' => leo.id, 'name' => 'Leo', 'recusa' => nil },
                             { 'tipo' => 'plataforma', 'id' => porta.autonomia_agent_id, 'name' => 'Sofia', 'recusa' => nil }
                           ])
    end

    it 'offers only agents from another system when the account has no Agents module' do
      sem_modulo = create(:account)
      dono = create(:user, account: sem_modulo, role: :administrator)
      caixa = create(:inbox, account: sem_modulo)
      Autonomia::Agents::Agent.create!(account: sem_modulo, name: 'Sofia', agent_type: 'custom')
      bot = create(:agent_bot, account: sem_modulo, name: 'Automação', outgoing_url: 'https://automacao.example.com/hook')

      get "/api/v1/accounts/#{sem_modulo.id}/autonomia/inboxes/#{caixa.id}/quem_atende", headers: dono.create_new_auth_token, as: :json

      expect(response.parsed_body['opcoes']).to eq([{ 'tipo' => 'webhook', 'id' => bot.id, 'name' => 'Automação', 'recusa' => nil }])
    end
  end

  it 'answers an empty list for an inbox without platform agents, with no feature flag on' do
    expect(account.feature_enabled?('autonomia_agents_journey')).to be(false)

    expect(agentes).to eq([])
    expect(response.parsed_body['primeiro']).to be_nil
    expect(response).to have_http_status(:ok)
  end

  it 'refuses an agent who cannot open the inbox settings' do
    agent = create(:user, account: account, role: :agent)

    agentes(agent)

    expect(response).to have_http_status(:unauthorized)
  end

  it 'lets an agent who is a member of the inbox read it, like the inbox settings page' do
    agent = create(:user, account: account, role: :agent)
    create(:inbox_member, user: agent, inbox: inbox)
    vincular!('Clara', 'porta')

    expect(agentes(agent).pluck('name')).to eq(['Clara'])
  end

  it 'does not read an inbox of another account' do
    outra = create(:inbox, account: create(:account))

    alheia = "/api/v1/accounts/#{account.id}/autonomia/inboxes/#{outra.id}/quem_atende"
    get alheia, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
  end
end
