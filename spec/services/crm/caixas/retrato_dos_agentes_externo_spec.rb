require 'rails_helper'

# chat#1648 — Quem cuida do quê? mostra "Agente externo: {nome}, atende primeiro" com o que o retrato diz em
# `ai_agents.externo`. Só na caixa aberta (`detalhe`); a lista não consulta.
RSpec.describe Crm::Caixas::RetratoDosAgentes do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:externo) { create(:agent_bot, account: account, name: 'Robo n8n', outgoing_url: 'https://n8n.example.com/hook') }

  def retrato(detalhe: true)
    described_class.new(account: account, inbox_ids: [inbox.id], pode_mudar: false, detalhe: detalhe).caixa(inbox.id)
  end

  it 'exposes the external agent of the inbox' do
    AgentBotInbox.create!(inbox: inbox, agent_bot: externo, account: account)

    expect(retrato[:externo]).to eq({ id: externo.id, name: 'Robo n8n' })
  end

  it 'has no external agent when the bot is the mirror of the porta' do
    agente = Autonomia::Agents::Agent.create!(account: account, name: 'Clara', agent_type: 'custom')
    espelho = create(:agent_bot, account: account, name: 'Clara', outgoing_url: nil)
    AgentBotInbox.create!(inbox: inbox, agent_bot: espelho, account: account)
    Autonomia::Agents::AgentInbox.create!(agent: agente, inbox: inbox, account: account, agent_bot: espelho)

    expect(retrato[:externo]).to be_nil
    expect(retrato[:porta]).to eq({ id: agente.id, name: 'Clara' })
  end

  it 'never calls the mirror of a deleted porta an external agent, like RobosSemEspelho' do
    agente = Autonomia::Agents::Agent.create!(account: account, name: 'Clara', agent_type: 'custom')
    espelho = create(:agent_bot, account: account, name: 'Clara', outgoing_url: nil)
    AgentBotInbox.create!(inbox: inbox, agent_bot: espelho, account: account)
    Autonomia::Agents::AgentInbox.create!(agent: agente, inbox: inbox, account: account, agent_bot: espelho,
                                          deleted_at: Time.current)

    expect(retrato[:externo]).to be_nil
  end

  it 'picks the row that is not a mirror when the inbox has more than one, oldest first' do
    agente = Autonomia::Agents::Agent.create!(account: account, name: 'Clara', agent_type: 'custom')
    espelho = create(:agent_bot, account: account, name: 'Clara', outgoing_url: nil)
    AgentBotInbox.create!(inbox: inbox, agent_bot: espelho, account: account)
    Autonomia::Agents::AgentInbox.create!(agent: agente, inbox: inbox, account: account, agent_bot: espelho)
    AgentBotInbox.create!(inbox: inbox, agent_bot: externo, account: account)
    outro = create(:agent_bot, account: account, name: 'Outro', outgoing_url: 'https://outro.example.com/hook')
    AgentBotInbox.create!(inbox: inbox, agent_bot: outro, account: account)

    expect(retrato[:externo]).to eq({ id: externo.id, name: 'Robo n8n' })
  end

  it 'has no external agent for an inactive bot or an inbox without bot' do
    expect(retrato[:externo]).to be_nil

    AgentBotInbox.create!(inbox: inbox, agent_bot: externo, account: account, status: :inactive)
    expect(retrato[:externo]).to be_nil
  end

  it 'leaves the key out of the list (no detalhe)' do
    AgentBotInbox.create!(inbox: inbox, agent_bot: externo, account: account)

    expect(retrato(detalhe: false)).not_to have_key(:externo)
  end
end
