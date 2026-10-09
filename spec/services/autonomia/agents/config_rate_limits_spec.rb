require 'rails_helper'

RSpec.describe Autonomia::Agents::Config do
  describe '.ai_rate_limits' do
    it 'provides the documented defaults when no overrides are configured' do
      with_modified_env RATE_LIMIT_AUTONOMIA_BUILD_THREADS: nil, RATE_LIMIT_AUTONOMIA_TEST: nil,
                        RATE_LIMIT_AUTONOMIA_SUGGEST: nil, RATE_LIMIT_AUTONOMIA_COPY_SOURCE: nil do
        expect(described_class.ai_rate_limits).to eq(build_threads: 60, test: 30, suggest: 30, copy_source: 10)
      end
    end

    it 'accepts positive integer overrides without changing other budgets' do
      with_modified_env RATE_LIMIT_AUTONOMIA_BUILD_THREADS: '12', RATE_LIMIT_AUTONOMIA_TEST: '9',
                        RATE_LIMIT_AUTONOMIA_SUGGEST: '8', RATE_LIMIT_AUTONOMIA_COPY_SOURCE: '7' do
        expect(described_class.ai_rate_limits).to eq(build_threads: 12, test: 9, suggest: 8, copy_source: 7)
      end
    end

    %w[0 -1 1.5 invalid].each do |invalid_limit|
      it "rejects the invalid limit #{invalid_limit} instead of silently coercing it" do
        with_modified_env RATE_LIMIT_AUTONOMIA_TEST: invalid_limit do
          expect { described_class.ai_rate_limits }.to raise_error(ArgumentError)
        end
      end
    end
  end
end
