require 'rails_helper'

RSpec.describe Crm::Ai::Pricing do
  describe '.rate' do
    it 'returns zero rate for an unknown model with no ENV override' do
      expect(described_class.rate('modelo-inexistente')).to eq(input: 0.0, cached: 0.0, output: 0.0)
    end

    it 'returns the OpenAI table rate for the default known models' do
      expect(described_class.rate('gpt-5.4')).to eq(input: 2.5, cached: 0.25, output: 15.0)
      expect(described_class.rate('gpt-5.4-mini')).to eq(input: 0.75, cached: 0.075, output: 4.5)
    end

    it 'reads an ENV override normalizing the model into the price var name' do
      ClimateControl.modify(CRM_AI_PRICE_GPT_5_4_MINI: '0.15,0.015,0.6') do
        expect(described_class.rate('gpt-5.4-mini')).to eq(input: 0.15, cached: 0.015, output: 0.6)
      end
    end

    it 'normalizes every non-alphanumeric char in the model to underscore' do
      ClimateControl.modify(CRM_AI_PRICE_GPT_5_4: '2.5,0.25,10') do
        expect(described_class.rate('gpt-5.4')).to eq(input: 2.5, cached: 0.25, output: 10.0)
      end
    end

    it 'exposes the cache write rate for the 5.6 family' do
      expect(described_class.rate('gpt-5.6-sol')).to eq(input: 5.0, cached: 0.5, cache_write: 6.25, output: 30.0)
      expect(described_class.rate('gpt-5.6-luna')).to eq(input: 1.0, cached: 0.1, cache_write: 1.25, output: 6.0)
    end

    it 'omits the cache write rate for models that do not charge it' do
      expect(described_class.rate('gpt-5.4')).not_to have_key(:cache_write)
    end

    it 'reads an optional fourth ENV field as the cache write rate' do
      ClimateControl.modify(CRM_AI_PRICE_GPT_5_6_LUNA: '1,0.1,6,1.25') do
        expect(described_class.rate('gpt-5.6-luna')).to eq(input: 1.0, cached: 0.1, output: 6.0, cache_write: 1.25)
      end
    end

    it 'keeps the three-field ENV format working without a cache write rate' do
      ClimateControl.modify(CRM_AI_PRICE_GPT_5_6_LUNA: '1,0.1,6') do
        expect(described_class.rate('gpt-5.6-luna')).not_to have_key(:cache_write)
      end
    end
  end

  describe '.cost' do
    it 'is zero for an unknown model with no ENV override' do
      expect(described_class.cost(model: 'modelo-inexistente', input_tokens: 1000, output_tokens: 500)).to eq(0.0)
    end

    it 'uses the default table rate for a known model' do
      # gpt-5.4: input 2.5, cached 0.25, output 15 (USD/1M)
      # (1000*2.5 + 500*15) / 1_000_000 = 10000 / 1_000_000
      cost = described_class.cost(model: 'gpt-5.4', input_tokens: 1000, output_tokens: 500)
      expect(cost).to be_within(1e-9).of(0.01)
    end

    it 'charges cached tokens at the discounted rate and the remaining input at full rate' do
      ClimateControl.modify(CRM_AI_PRICE_GPT_5_4: '2.5,0.25,10') do
        # input=1000 inclui 200 cacheados -> billable_input = 800
        # (800*2.5 + 200*0.25 + 500*10) / 1_000_000 = 7050 / 1_000_000
        cost = described_class.cost(model: 'gpt-5.4', input_tokens: 1000, cached_tokens: 200, output_tokens: 500)
        expect(cost).to be_within(1e-9).of(0.00705)
      end
    end

    it 'never lets billable input go negative when cached exceeds input' do
      ClimateControl.modify(CRM_AI_PRICE_GPT_5_4: '2.5,0.25,10') do
        cost = described_class.cost(model: 'gpt-5.4', input_tokens: 100, cached_tokens: 500, output_tokens: 0)
        # billable_input clamped a 0 -> só os 500 cacheados a 0.25
        expect(cost).to be_within(1e-9).of(500 * 0.25 / 1_000_000.0)
      end
    end

    it 'charges cache write tokens at their own rate instead of the full input rate' do
      # gpt-5.6-luna: input 1.0, cached 0.1, cache_write 1.25, output 6.0
      # input=1000 inclui 800 escritos em cache -> billable_input = 200
      # (200*1.0 + 800*1.25 + 500*6.0) / 1_000_000 = 4200 / 1_000_000
      cost = described_class.cost(model: 'gpt-5.6-luna', input_tokens: 1000, cache_write_tokens: 800, output_tokens: 500)
      expect(cost).to be_within(1e-9).of(0.0042)
    end

    it 'prices the real probe payload from the 5.6 API' do
      # Medido em produção: 1a chamada (cache miss) input=4176 cache_write=4173 output=5
      # (3*1.0 + 4173*1.25 + 5*6.0) / 1_000_000
      cost = described_class.cost(model: 'gpt-5.6-luna', input_tokens: 4176, cache_write_tokens: 4173, output_tokens: 5)
      expect(cost).to be_within(1e-9).of(0.00524925)
    end

    it 'discounts cached and cache write from the billable input together' do
      # input=1000 = 300 cacheados + 500 escritos + 200 novos
      # (200*1.0 + 300*0.1 + 500*1.25 + 0) / 1_000_000 = 855 / 1_000_000
      cost = described_class.cost(model: 'gpt-5.6-luna', input_tokens: 1000, cached_tokens: 300,
                                  cache_write_tokens: 500, output_tokens: 0)
      expect(cost).to be_within(1e-9).of(0.000855)
    end

    it 'falls back to the input rate when the model has no cache write rate' do
      # gpt-5.4 não cobra cache write: os 800 escritos custam a tarifa cheia de input (2.5)
      # (200*2.5 + 800*2.5) / 1_000_000 = 2500 / 1_000_000
      cost = described_class.cost(model: 'gpt-5.4', input_tokens: 1000, cache_write_tokens: 800, output_tokens: 0)
      expect(cost).to be_within(1e-9).of(0.0025)
    end

    it 'keeps the previous cost unchanged when no cache write is reported' do
      cost = described_class.cost(model: 'gpt-5.6-luna', input_tokens: 1000, cached_tokens: 200, output_tokens: 500)
      # (800*1.0 + 200*0.1 + 500*6.0) / 1_000_000 = 3820 / 1_000_000
      expect(cost).to be_within(1e-9).of(0.00382)
    end
  end
end
