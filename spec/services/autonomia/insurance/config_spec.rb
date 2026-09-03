# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Autonomia::Insurance::Config do
  let(:account) { create(:account) }

  def stub_master(value)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('INSURANCE_QUOTING_ENABLED', false).and_return(value)
  end

  describe '.enabled?' do
    it 'is false when the global kill-switch is off, even for an enabled account' do
      stub_master('false')
      described_class.enable_for!(account)

      expect(described_class.enabled?(account.reload)).to be false
    end

    it 'is false when the kill-switch is on but the account is not marked' do
      stub_master('true')

      expect(described_class.enabled?(account)).to be false
    end

    it 'is true only when the kill-switch is on and the account is marked' do
      stub_master('true')
      described_class.enable_for!(account)

      expect(described_class.enabled?(account.reload)).to be true
    end

    it 'never returns nil (strict boolean for the account payload)' do
      stub_master('true')

      expect(described_class.enabled?(nil)).to be false
      expect(described_class.enabled?(account)).to be false
    end

    it 'is isolated from the Agents and Prospecting gates' do
      stub_master('true')
      account.update!(internal_attributes: { 'autonomia_agents_enabled' => true, 'autonomia_prospecting_enabled' => true })

      expect(described_class.enabled?(account.reload)).to be false
    end
  end

  describe '.account_enabled?' do
    it 'reads the internal attribute regardless of the kill-switch' do
      stub_master('false')
      described_class.enable_for!(account)

      expect(described_class.account_enabled?(account.reload)).to be true
    end
  end

  describe '.enable_for! / .disable_for!' do
    it 'toggles the account internal attribute without touching other keys' do
      account.update!(internal_attributes: { 'autonomia_prospecting_enabled' => true })

      described_class.enable_for!(account)
      expect(account.reload.internal_attributes).to include('autonomia_insurance_enabled' => true,
                                                            'autonomia_prospecting_enabled' => true)

      described_class.disable_for!(account)
      expect(account.reload.internal_attributes['autonomia_insurance_enabled']).to be false
    end
  end
end
