require 'rails_helper'

RSpec.describe Whatsapp::Pricing do
  describe '.per_message' do
    it 'reads the factory table of installation_config.yml when nothing was saved' do
      price = described_class.per_message('MARKETING')

      expect(price.amount).to eq(BigDecimal('0.3217'))
      expect(price).to have_attributes(category: 'marketing', currency: 'BRL', country: 'BR', effective_from: '2026-10-01')
      expect(%w[utility authentication service].map { |category| described_class.per_message(category).amount })
        .to all(eq(BigDecimal('0.035')))
    end

    it 'reads the table saved in the Super Admin, as JSON text or as a map' do
      table = { 'BR' => { 'currency' => 'BRL', 'effective_from' => '2027-01-01', 'prices' => { 'marketing' => '0.40' } } }
      create(:installation_config, name: described_class::CONFIG_KEY, value: table.to_json)
      GlobalConfig.clear_cache(described_class::CONFIG_KEY)

      expect(described_class.per_message('marketing')).to have_attributes(amount: BigDecimal('0.4'), effective_from: '2027-01-01')
      expect(described_class.per_message('utility')).to be_nil
    end

    it 'gives nil for an unknown category or country' do
      expect(described_class.per_message('promotion')).to be_nil
      expect(described_class.per_message('marketing', country: 'US')).to be_nil
    end

    it 'gives nil when the saved table is broken' do
      create(:installation_config, name: described_class::CONFIG_KEY, value: '{not json')
      GlobalConfig.clear_cache(described_class::CONFIG_KEY)

      expect(described_class.per_message('marketing')).to be_nil
    end
  end

  describe '.free_tier' do
    it 'gives the free service messages per number per month' do
      expect(described_class.free_tier('service')).to eq(messages: 1000, period: 'month', per: 'phone_number')
      expect(described_class.free_tier('marketing')).to be_nil
    end
  end
end
