require 'rails_helper'

RSpec.describe Instagram::Testers::RateLimiter do
  it 'limits each account and actor before the next provider request' do
    travel_to Time.zone.local(2026, 1, 1, 12, 0, 0) do
      key = "instagram_testers:rate:16:2:#{Time.current.to_i / described_class::WINDOW}"
      Redis::Alfred.delete(key)
      described_class::LIMIT.times { described_class.check!(account_id: 16, actor_id: 2) }
      expect { described_class.check!(account_id: 16, actor_id: 2) }
        .to(raise_error { |error| expect(error.code).to eq('rate_limited') })
      expect { described_class.check!(account_id: 17, actor_id: 2) }.not_to raise_error
      expect { described_class.check!(account_id: 16, actor_id: 3) }.not_to raise_error
      travel described_class::WINDOW.seconds
      expect { described_class.check!(account_id: 16, actor_id: 2) }.not_to raise_error
    end
  end
end
