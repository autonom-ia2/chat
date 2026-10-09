require 'rails_helper'

RSpec.describe Autonomia::Agents::Config do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true, 'untouched' => 'preserve' }) }

  describe '.redesign_enabled?' do
    it 'defaults off without a master flag or account opt-in' do
      with_modified_env AUTONOMIA_AGENTS_REDESIGN: nil do
        expect(described_class.redesign_enabled?(account)).to be(false)
      end
    end

    it 'requires both the master flag and the account opt-in' do
      with_modified_env AUTONOMIA_AGENTS_REDESIGN: 'true' do
        expect(described_class.redesign_enabled?(account)).to be(false)
        account.update!(internal_attributes: account.internal_attributes.merge('autonomia_agents_redesign' => true))
        expect(described_class.redesign_enabled?(account)).to be(true)
        expect(described_class.redesign_enabled?(create(:account))).to be(false)
      end

      with_modified_env AUTONOMIA_AGENTS_REDESIGN: 'false' do
        expect(described_class.redesign_enabled?(account)).to be(false)
      end
    end
  end

  describe 'account rollout helpers' do
    it 'changes only the redesign opt-in and preserves agents, threads and the existing product gate' do
      agent = Autonomia::Agents::Agent.create!(account: account, name: 'Local draft', agent_type: 'custom')
      thread = Autonomia::Agents::BuildThread.create!(account: account, agent: agent,
                                                      messages: [{ role: 'user', content: 'Synthetic draft' }])

      with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true', AUTONOMIA_AGENTS_REDESIGN: 'true' do
        described_class.enable_redesign_for!(account)
        expect(described_class.redesign_enabled?(account.reload)).to be(true)
        described_class.disable_redesign_for!(account)
        expect(described_class.redesign_enabled?(account.reload)).to be(false)
        expect(described_class.enabled?(account)).to be(true)
      end

      expect(account.internal_attributes).to include('untouched' => 'preserve', 'autonomia_agents_enabled' => true)
      expect(agent.reload).not_to be_deleted
      expect(thread.reload.messages).to eq([{ 'role' => 'user', 'content' => 'Synthetic draft' }])
      expect(thread.autonomia_agent_id).to eq(agent.id)
    end
  end
end
