require 'rails_helper'

# chat#1720 — dois "Salvar" ao mesmo tempo pedindo o mesmo canal para agentes diferentes. A trava (agentes → caixas)
# põe um depois do outro: no fim só um atende primeiro no canal, cada agente fica inteiro (porta e áreas que pediu, ou
# nada mudou) e ninguém fica sem onde trabalhar no meio do caminho.
RSpec.describe Autonomia::Agents::OndeAtende, :relationships_committed_fixtures do
  self.use_transactional_tests = false

  let!(:account) { create(:account, internal_attributes: { 'autonomia_agents_fase2' => true }) }
  let!(:disputado) { create(:inbox, account: account, name: 'HUBBER COMUNIDADE') }
  let!(:do_hubber) { create(:inbox, account: account, name: 'Comercial') }
  let!(:do_leo) { create(:inbox, account: account, name: 'hub2you') }
  let!(:hubber) { agente('Hubber') }
  let!(:leo) { agente('Leo') }

  before do
    conectar(hubber, do_hubber)
    conectar(leo, do_leo)
  end

  after do
    Autonomia::Agents::Agent.where(account_id: account.id).find_each(&:destroy!)
    AgentBot.where(account_id: account.id).find_each(&:destroy!)
    account.inboxes.find_each(&:destroy!)
    account.destroy!
    Audited::Audit.where(associated: account).or(Audited::Audit.where(auditable: account)).delete_all
  end

  def agente(nome)
    Autonomia::Agents::Agent.create!(account: account, name: nome, agent_type: 'custom', status: :active, enabled: true)
  end

  def conectar(agent, caixa)
    Autonomia::Agents::Operate::InboxConnector.new(agent: agent, inbox: caixa).perform(connect: true)
  end

  def salvar_em_paralelo(*agentes)
    agentes.map do |agent|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |conexao|
          conexao.execute("SET lock_timeout = '10s'")
          described_class.new(agent: Autonomia::Agents::Agent.find(agent.id), primeiro: Inbox.find(disputado.id), areas: []).perform
        end
      end
    end.map(&:value)
  end

  def portas(agent)
    Autonomia::Agents::AgentInbox.kept.porta.where(autonomia_agent_id: agent.id).pluck(:inbox_id)
  end

  it 'ends with exactly one agent first in the channel and each agent whole' do
    resultados = salvar_em_paralelo(hubber, leo)

    expect(resultados.map(&:code)).to all(be_nil.or(eq(:mudou_agora)))
    expect(Autonomia::Agents::AgentInbox.kept.porta.where(inbox_id: disputado.id).count).to eq(1)
    dono = Autonomia::Agents::AgentInbox.kept.porta.find_by(inbox_id: disputado.id).autonomia_agent_id
    outro = [hubber, leo].find { |agent| agent.id != dono }
    expect(portas(Autonomia::Agents::Agent.find(dono))).to eq([disputado.id])
    # O outro: ou nada mudou (recusa), ou entrou e depois saiu pela troca do segundo (sem caixa, para).
    expect(portas(outro)).to be_in([[outro == hubber ? do_hubber.id : do_leo.id], []])
  end
end
