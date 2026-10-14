require 'rails_helper'

RSpec.describe Crm::FollowUps::SeriesSchedule do
  def series(**attrs)
    Crm::FollowUpSeries.new({ timezone: 'America/Sao_Paulo', ends_mode: :never, weekdays: [] }.merge(attrs))
  end

  def local(text)
    ActiveSupport::TimeZone['America/Sao_Paulo'].parse(text)
  end

  def dates(schedule, limit)
    schedule.each_occurrence.first(limit).map { |time| time.strftime('%Y-%m-%d %H:%M') }
  end

  it 'repeats every day keeping the wall clock hour' do
    schedule = series(frequency: :daily, starts_at: local('2026-10-14 10:00')).schedule
    expect(dates(schedule, 3)).to eq(['2026-10-14 10:00', '2026-10-15 10:00', '2026-10-16 10:00'])
  end

  it 'skips saturday and sunday when only weekdays' do
    schedule = series(frequency: :daily, weekdays_only: true, starts_at: local('2026-10-16 18:00')).schedule
    expect(dates(schedule, 2)).to eq(['2026-10-16 18:00', '2026-10-19 18:00'])
  end

  it 'repeats on the chosen weekdays' do
    schedule = series(frequency: :weekly, weekdays: [1, 3], starts_at: local('2026-10-19 09:00')).schedule
    expect(dates(schedule, 4)).to eq(['2026-10-19 09:00', '2026-10-21 09:00', '2026-10-26 09:00', '2026-10-28 09:00'])
  end

  it 'falls back to the last day in short months and returns to the chosen day after' do
    schedule = series(frequency: :monthly, starts_at: local('2027-01-31 09:00')).schedule
    expect(dates(schedule, 3)).to eq(['2027-01-31 09:00', '2027-02-28 09:00', '2027-03-31 09:00'])
  end

  it 'repeats every year' do
    schedule = series(frequency: :yearly, starts_at: local('2026-10-22 09:00')).schedule
    expect(dates(schedule, 2)).to eq(['2026-10-22 09:00', '2027-10-22 09:00'])
  end

  it 'stops after the chosen number of times' do
    schedule = series(frequency: :weekly, weekdays: [1, 3], ends_mode: :after_count, occurrences_count: 3,
                      starts_at: local('2026-10-19 09:00')).schedule
    expect(dates(schedule, 10).size).to eq(3)
  end

  it 'stops after the chosen last day' do
    schedule = series(frequency: :daily, ends_mode: :on_date, ends_on: Date.new(2026, 10, 15),
                      starts_at: local('2026-10-14 10:00')).schedule
    expect(dates(schedule, 10)).to eq(['2026-10-14 10:00', '2026-10-15 10:00'])
  end

  it 'keeps 10:00 across a daylight saving change' do
    schedule = Crm::FollowUpSeries.new(timezone: 'America/New_York', ends_mode: :never, weekdays: [], frequency: :daily,
                                       starts_at: ActiveSupport::TimeZone['America/New_York'].parse('2026-10-31 10:00')).schedule
    expect(schedule.each_occurrence.first(3).map { |time| time.strftime('%H:%M') }).to eq(%w[10:00 10:00 10:00])
  end

  it 'lists the next times after a moment and inside a window' do
    schedule = series(frequency: :daily, starts_at: local('2026-10-14 10:00')).schedule
    expect(schedule.next_after(local('2026-10-15 10:00')).strftime('%d')).to eq('16')
    expect(schedule.between(local('2026-10-20 00:00'), local('2026-10-21 23:59')).size).to eq(2)
  end
end
