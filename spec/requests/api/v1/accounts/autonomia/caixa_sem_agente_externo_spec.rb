require 'rails_helper'

# chat#1648 — marcação por caixa: a aba "Agente externo" (InboxesController#set_agent_bot) não pluga agente externo em
# caixa atendida por agente da plataforma, nem desconecta o espelho da porta. Vale para todas as contas.
RSpec.describe 'Inbox set_agent_bot with platform agents', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:externo) { create(:agent_bot, account: account, name: 'Robo n8n', outgoing_url: 'https://n8n.example.com/hook') }
  let(:url) { "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/set_agent_bot" }

  def agente(nome)
    Autonomia::Agents::Agent.create!(account: account, name: nome, agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda o cliente.')
  end

  # A porta como o InboxConnector a deixa: espelho com AgentBotInbox na caixa.
  def porta!(nome = 'Clara')
    espelho = create(:agent_bot, account: account, name: nome, outgoing_url: nil)
    AgentBotInbox.create!(inbox: inbox, agent_bot: espelho, account: account)
    Autonomia::Agents::AgentInbox.create!(agent: agente(nome), inbox: inbox, account: account, agent_bot: espelho)
  end

  # A área: espelho próprio SEM AgentBotInbox (caixa só de pessoas).
  def area!(nome = 'Maria')
    espelho = create(:agent_bot, account: account, name: nome, outgoing_url: nil)
    Autonomia::Agents::AgentInbox.create!(agent: agente(nome), inbox: inbox, account: account, agent_bot: espelho,
                                          papel: 'area')
  end

  def plugar(agent_bot_id)
    post url, params: { agent_bot: agent_bot_id }, headers: admin.create_new_auth_token, as: :json
  end

  def robo_da_caixa
    AgentBotInbox.where(inbox_id: inbox.id).pluck(:agent_bot_id)
  end

  it 'refuses an external agent on an inbox with a porta and keeps the mirror' do
    porta = porta!

    plugar(externo.id)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['code']).to eq('caixa_com_agente_da_plataforma')
    expect(response.parsed_body['error']).to be_present
    expect(robo_da_caixa).to eq([porta.agent_bot_id])
  end

  it 'refuses an external agent on an inbox with only an area' do
    area!

    plugar(externo.id)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['code']).to eq('caixa_com_agente_da_plataforma')
    expect(robo_da_caixa).to be_empty
  end

  it 'refuses the mirror of an area, which is not the porta of this inbox' do
    area = area!

    plugar(area.agent_bot_id)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(robo_da_caixa).to be_empty
  end

  it 'accepts an external agent on an inbox without platform agents' do
    plugar(externo.id)

    expect(response).to have_http_status(:ok)
    expect(robo_da_caixa).to eq([externo.id])
  end

  it 'accepts an external agent when the platform link was deleted' do
    porta!.update!(deleted_at: Time.current)

    plugar(externo.id)

    expect(response).to have_http_status(:ok)
    expect(robo_da_caixa).to eq([externo.id])
  end

  it 'accepts the mirror of the porta of this inbox' do
    porta = porta!

    plugar(porta.agent_bot_id)

    expect(response).to have_http_status(:ok)
    expect(robo_da_caixa).to eq([porta.agent_bot_id])
  end

  it 'refuses to disconnect the mirror of a porta' do
    porta = porta!

    plugar(nil)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['code']).to eq('desconectar_agente_da_plataforma')
    expect(robo_da_caixa).to eq([porta.agent_bot_id])
  end

  it 'lets an inbox with only an area disconnect (there is no mirror to drop)' do
    area!

    plugar(nil)

    expect(response).to have_http_status(:ok)
  end

  it 'does not count a platform agent of another inbox' do
    outra = create(:inbox, account: account)
    espelho = create(:agent_bot, account: account, outgoing_url: nil)
    Autonomia::Agents::AgentInbox.create!(agent: agente('Outra'), inbox: outra, account: account, agent_bot: espelho)

    plugar(externo.id)

    expect(response).to have_http_status(:ok)
  end
end
