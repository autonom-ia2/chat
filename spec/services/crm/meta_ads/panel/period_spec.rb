require 'rails_helper'

RSpec.describe Crm::MetaAds::Panel::Period do
  let(:today) { Date.new(2026, 10, 21) }

  def period(key, first_ad_day: nil)
    described_class.new(key, today: today, first_ad_day: first_ad_day)
  end

  describe '.key_for' do
    it 'takes the period name and keeps the old days param working' do
      expect(described_class.key_for(period: 'last_month')).to eq('last_month')
      expect(described_class.key_for(days: '7')).to eq('7d')
      expect(described_class.key_for(days: 30)).to eq('30d')
      expect(described_class.key_for(period: 'all', days: 7)).to eq('all')
    end

    it 'falls back to 30 days for anything unknown' do
      expect(described_class.key_for(period: 'ontem')).to eq('30d')
      expect(described_class.key_for(days: 15)).to eq('30d')
      expect(described_class.key_for).to eq('30d')
    end
  end

  it 'counts the rolling periods back from today, today included' do
    expect([period('7d').first_day, period('7d').last_day, period('7d').days]).to eq([Date.new(2026, 10, 15), today, 7])
    expect(period('90d').days).to eq(90)
    expect(period('30d')).to be_open
    expect(period('30d')).to be_rolling(30)
    expect(period('90d')).not_to be_rolling(30)
  end

  it 'covers this month up to today and the whole last month, which is closed' do
    expect([period('this_month').first_day, period('this_month').last_day]).to eq([Date.new(2026, 10, 1), today])
    last = period('last_month')
    expect([last.first_day, last.last_day, last.days]).to eq([Date.new(2026, 9, 1), Date.new(2026, 9, 30), 30])
    expect(last).not_to be_open
  end

  it 'starts all time at the first ad, capped at what Meta still returns' do
    expect(period('all', first_ad_day: -> { Date.new(2026, 6, 28) }).first_day).to eq(Date.new(2026, 6, 28))
    expect(period('all', first_ad_day: -> { Date.new(2020, 1, 1) }).first_day).to eq(Date.new(2023, 9, 21))
    expect(period('all', first_ad_day: -> {}).first_day).to eq(today)
  end

  it 'only looks for the first ad when all time is asked' do
    first_ad_day = -> { raise 'should not be called' }

    expect(period('30d', first_ad_day: first_ad_day).days).to eq(30)
  end

  it 'turns an unknown key into the default' do
    expect(period('qualquer').key).to eq('30d')
  end
end
