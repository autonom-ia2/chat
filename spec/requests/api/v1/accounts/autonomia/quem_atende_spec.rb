require 'rails_helper'

# chat#1648 — a aba "Agente externo" da caixa lê quais agentes da plataforma atendem ali. Sem flag (módulo, jornada ou
# Fase 2) e com a autorização da tela de configuração da caixa.
RSpec.describe 'Autonomia quem_atende API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:url) { "/api/v1/accounts/#{account.id}/autonomia/inboxes/#{inbox.id}/quem_atende" }

  def vincular!(nome, papel, caixa: inbox)
    agente = Autonomia::Agents::Agent.create!(account: account, name: nome, agent_type: 'custom')
    espelho = create(:agent_bot, account: account, name: nome, outgoing_url: nil)
    Autonomia::Agents::AgentInbox.create!(agent: agente, inbox: caixa, account: account, agent_bot: espelho, papel: papel)
  end

  def agentes(user = admin)
    get url, headers: user.create_new_auth_token, as: :json
    response.parsed_body['agentes']
  end

  it 'lists the porta first and then the areas by name, only kept links' do
    vincular!('Zeca', 'area')
    porta = vincular!('Clara', 'porta')
    vincular!('Ana', 'area')
    vincular!('Velho', 'area').update!(deleted_at: Time.current)
    vincular!('De outra caixa', 'porta', caixa: create(:inbox, account: account))

    expect(agentes).to eq([
                            { 'id' => porta.autonomia_agent_id, 'name' => 'Clara', 'papel' => 'porta' },
                            { 'id' => Autonomia::Agents::Agent.find_by(name: 'Ana').id, 'name' => 'Ana', 'papel' => 'area' },
                            { 'id' => Autonomia::Agents::Agent.find_by(name: 'Zeca').id, 'name' => 'Zeca', 'papel' => 'area' }
                          ])
    expect(response).to have_http_status(:ok)
  end

  it 'answers an empty list for an inbox without platform agents, with no feature flag on' do
    expect(account.feature_enabled?('autonomia_agents_journey')).to be(false)

    expect(agentes).to eq([])
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
