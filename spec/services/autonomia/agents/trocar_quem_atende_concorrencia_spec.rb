require 'rails_helper'

# #1648 — a troca da aba "Agente de IA" (TrocarQuemAtende, pondo um agente de outro sistema) e o "começar a atender
# neste canal" (InboxConnector#connect!) na mesma caixa, ao mesmo tempo. agent_bot_inboxes não tem índice único por
# caixa: sem a trava da caixa nos dois caminhos, cada um conferia a caixa antes do commit do outro e os dois gravavam
# (porta + agente de outro sistema). Com a trava (agentes → caixa), um espera o outro, enxerga o que ele gravou e recusa:
# o connect com inbox_has_webhook_bot, a troca com mudou_agora (a porta nova é de um agente que ela não travou).
RSpec.describe Autonomia::Agents::TrocarQuemAtende, :relationships_committed_fixtures do
  self.use_transactional_tests = false

  let!(:account) { create(:account) }
  let!(:inbox) { create(:inbox, account: account) }
  let!(:agente) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bia', agent_type: 'custom', status: :active, enabled: true)
  end
  let!(:outro_sistema) { create(:agent_bot, account: account, name: 'Automação', outgoing_url: 'https://automacao.example.com/hook') }
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
    allow_any_instance_of(Autonomia::Agents::Operate::InboxConnector).to receive(:webhook_bot_present?).and_wrap_original(&esperar) # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(described_class).to receive(:ler_a_caixa).and_wrap_original(&esperar) # rubocop:disable RSpec/AnyInstance
  end

  after do
    Autonomia::Agents::AgentInbox.where(account_id: account.id).delete_all
    AgentBotInbox.where(inbox_id: inbox.id).delete_all
    Autonomia::Agents::Agent.where(account_id: account.id).find_each(&:destroy!)
    AgentBot.where(account_id: account.id).find_each(&:destroy!)
    account.inboxes.find_each(&:destroy!)
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
    conectar = em_thread do
      Autonomia::Agents::Operate::InboxConnector.new(agent: Autonomia::Agents::Agent.find(agente.id), inbox: Inbox.find(inbox.id))
                                                .perform(connect: true)
    end
    trocar = em_thread do
      described_class.new(inbox: Inbox.find(inbox.id), alvo: { tipo: 'webhook', agent_bot: AgentBot.find(outro_sistema.id) }).perform
    end

    conexao = conectar.value
    troca = trocar.value

    expect(AgentBotInbox.where(inbox_id: inbox.id).count).to eq(1)
    expect([conexao.success?, troca.ok?]).to contain_exactly(true, false)
    if conexao.success?
      expect(troca.code).to eq(:mudou_agora)
      expect(AgentBotInbox.find_by(inbox_id: inbox.id).agent_bot_id).to eq(conexao.agent_inbox.agent_bot_id)
    else
      expect(conexao.error).to eq(:inbox_has_webhook_bot)
      expect(AgentBotInbox.find_by(inbox_id: inbox.id).agent_bot_id).to eq(outro_sistema.id)
    end
  end
end
