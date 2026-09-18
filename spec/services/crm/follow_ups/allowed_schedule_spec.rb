require 'rails_helper'

RSpec.describe Crm::FollowUps::AllowedSchedule do
  subject(:schedule) { described_class.new(config: config, timezone: 'America/Sao_Paulo') }

  let(:config) { { allowed_days: [1, 2, 3, 4, 5], quiet_hours: { start: 8, end: 20 } } }

  it 'moves a weekend evaluation to Monday at 8 in the contact timezone' do
    expect(schedule.next_at(Time.utc(2026, 9, 19, 13))).to eq(Time.utc(2026, 9, 21, 11))
  end

  it 'excludes the closing boundary on Friday' do
    expect(schedule.next_at(Time.utc(2026, 9, 18, 23))).to eq(Time.utc(2026, 9, 21, 11))
  end

  it 'keeps an allowed time unchanged' do
    time = Time.utc(2026, 9, 14, 15)
    expect(schedule.next_at(time)).to eq(time)
  end

  it 'preserves all days for legacy configurations' do
    config.delete(:allowed_days)
    time = Time.utc(2026, 9, 19, 15)
    expect(schedule.next_at(time)).to eq(time)
  end

  it 'handles the DST offset at the next allowed local morning' do
    config[:allowed_days] = [0]
    ny = described_class.new(config: config, timezone: 'America/New_York')
    expect(ny.next_at(Time.utc(2026, 3, 7, 23))).to eq(Time.utc(2026, 3, 8, 12))
  end

  it 'rejects an empty day selection' do
    config[:allowed_days] = []
    expect { schedule }.to raise_error(ArgumentError)
  end
end
