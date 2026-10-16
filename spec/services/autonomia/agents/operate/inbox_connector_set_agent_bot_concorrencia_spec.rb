require 'rails_helper'

# #1648 — "começar a atender neste canal" (InboxConnector#connect!) e a aba "Agente externo" (set_agent_bot) na mesma
# caixa, ao mesmo tempo. agent_bot_inboxes não tem índice único por caixa: sem a trava da caixa nos dois caminhos, cada
# um conferia a caixa antes do commit do outro e os dois gravavam (porta + agente externo). Com a trava (agente → caixa),
# um espera o outro, enxerga o que ele gravou e recusa.
RSpec.describe Autonomia::Agents::Operate::InboxConnector, :relationships_committed_fixtures do
  self.use_transactional_tests = false

  let!(:account) { create(:account, internal_attributes: { 'autonomia_agente_ia_por_caixa' => true }) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:inbox) { create(:inbox, account: account) }
  let!(:agente) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bia', agent_type: 'custom', status: :active, enabled: true)
  end
  let!(:externo) { create(:agent_bot, account: account, name: 'Robo n8n', outgoing_url: 'https://n8n.example.com/hook') }
  let(:chegou) { Queue.new }

  before do
    # Cada lado confere a caixa e espera o outro também ter conferido (ou 1 s). Sem a trava da caixa as duas conferências
    # acontecem antes de qualquer commit; com ela, o segundo nem chega a conferir enquanto o primeiro não termina.
    fila = chegou
    esperar = lambda do |original|
      resposta = original.call
      fila << true
      inicio = Time.current
      sleep 0.05 until fila.size >= 2 || inicio < 1.second.ago
      resposta
    end
    allow_any_instance_of(described_class).to receive(:webhook_bot_present?).and_wrap_original(&esperar) # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(Api::V1::Accounts::InboxesController).to receive(:codigo_da_recusa).and_wrap_original(&esperar) # rubocop:disable RSpec/AnyInstance
  end

  after do
    Autonomia::Agents::AgentInbox.where(account_id: account.id).delete_all
    AgentBotInbox.where(account_id: account.id).delete_all
    Autonomia::Agents::Agent.where(account_id: account.id).find_each(&:destroy!)
    AgentBot.where(account_id: account.id).find_each(&:destroy!)
    account.inboxes.find_each(&:destroy!)
    admin.destroy!
    account.destroy!
    Audited::Audit.where(associated: account).or(Audited::Audit.where(auditable: account)).delete_all
  end

  def em_thread(&)
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |conexao|
        conexao.execute("SET lock_timeout = '10s'")
        yield
      end
    end
  end

  it 'ends with a single AgentBotInbox and refuses one of the two' do
    token = admin.create_new_auth_token
    conectar = em_thread do
      described_class.new(agent: Autonomia::Agents::Agent.find(agente.id), inbox: Inbox.find(inbox.id)).perform(connect: true)
    end
    plugar = em_thread do
      sessao = ActionDispatch::Integration::Session.new(Rails.application)
      url = "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/set_agent_bot"
      sessao.post url, params: { agent_bot: externo.id }.to_json, headers: token.merge('CONTENT_TYPE' => 'application/json')
      sessao.response.status
    end

    resultado = conectar.value
    status = plugar.value

    expect(AgentBotInbox.where(inbox_id: inbox.id).count).to eq(1)
    expect([resultado.success?, status == 200]).to contain_exactly(true, false)
    if resultado.success?
      expect(status).to eq(422)
      expect(AgentBotInbox.find_by(inbox_id: inbox.id).agent_bot_id).to eq(resultado.agent_inbox.agent_bot_id)
    else
      expect(resultado.error).to eq(:inbox_has_webhook_bot)
      expect(AgentBotInbox.find_by(inbox_id: inbox.id).agent_bot_id).to eq(externo.id)
    end
  end
end
