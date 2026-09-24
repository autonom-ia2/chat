# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Autonomia::Prospecting::Config do
  describe '.enabled?' do
    let(:account) { create(:account) }

    it 'uses the account internal attribute' do
      expect(described_class.enabled?(account)).to be false

      account.update!(internal_attributes: { 'autonomia_prospecting_enabled' => true })

      expect(described_class.enabled?(account.reload)).to be true
    end
  end

  describe '.enable_for!' do
    it 'enables the account internal attribute' do
      account = create(:account)

      described_class.enable_for!(account)

      expect(account.reload.internal_attributes['autonomia_prospecting_enabled']).to be true
    end
  end

  describe '.disable_for!' do
    it 'disables the account internal attribute' do
      account = create(:account)
      account.update!(internal_attributes: { 'autonomia_prospecting_enabled' => true })

      described_class.disable_for!(account)

      expect(account.reload.internal_attributes['autonomia_prospecting_enabled']).to be false
    end
  end

  describe 'pesquisa (research)' do
    let(:account) { create(:account) }

    it 'começa desligada e liga e desliga pela chave própria, sem mexer no módulo' do
      described_class.enable_for!(account)
      expect(described_class.research_enabled?(account)).to be false

      described_class.enable_research_for!(account)
      expect(account.reload.internal_attributes['autonomia_prospecting_research_enabled']).to be true
      expect(described_class.research_enabled?(account)).to be true
      expect(described_class.enabled?(account)).to be true

      described_class.disable_research_for!(account)
      expect(described_class.research_enabled?(account.reload)).to be false
      expect(described_class.enabled?(account)).to be true
    end

    it 'não liga a pesquisa quando só o módulo é ligado' do
      described_class.enable_for!(account)

      expect(account.reload.internal_attributes).not_to have_key('autonomia_prospecting_research_enabled')
    end
  end
end
