require 'rails_helper'

RSpec.describe Sla::BusinessTimeCalculator do
  # America/Sao_Paulo is UTC-3 all year (no DST since 2019). 2026-09-02 is a Wednesday.
  let(:account) { create(:account) }
  let(:schedule) { create(:crm_service_schedule, account: account, weekdays: [1, 2, 3, 4, 5], hours: [['09:00', '18:00']]) }
  let(:calculator) { described_class.new(schedule: schedule) }

  def brt(text)
    ActiveSupport::TimeZone['America/Sao_Paulo'].parse(text)
  end

  describe '#deadline' do
    it 'adds the threshold inside a single block' do
      expect(calculator.deadline(brt('2026-09-02 10:00'), 30.minutes)).to eq(brt('2026-09-02 10:30'))
    end

    it 'starts counting at the block opening when the start is before business hours' do
      expect(calculator.deadline(brt('2026-09-02 07:00'), 30.minutes)).to eq(brt('2026-09-02 09:30'))
    end

    it 'lands exactly on the block end when the threshold consumes the rest of the block' do
      expect(calculator.deadline(brt('2026-09-02 17:30'), 30.minutes)).to eq(brt('2026-09-02 18:00'))
    end

    it 'carries the remainder into the next day when the start is after closing (overnight)' do
      expect(calculator.deadline(brt('2026-09-02 17:45'), 30.minutes)).to eq(brt('2026-09-03 09:15'))
      expect(calculator.deadline(brt('2026-09-02 19:00'), 30.minutes)).to eq(brt('2026-09-03 09:30'))
    end

    it 'skips the weekend when the schedule has no Saturday or Sunday blocks' do
      expect(calculator.deadline(brt('2026-09-04 17:45'), 30.minutes)).to eq(brt('2026-09-07 09:15'))
      expect(calculator.deadline(brt('2026-09-05 10:00'), 1.hour)).to eq(brt('2026-09-07 10:00'))
    end

    it 'spans several business days' do
      # Wed 16:00 -> 2h left Wed, 9h Thu, 1h Fri
      expect(calculator.deadline(brt('2026-09-02 16:00'), 12.hours)).to eq(brt('2026-09-04 10:00'))
    end

    it 'returns the start itself for a zero threshold' do
      start = brt('2026-09-02 19:00')

      expect(calculator.deadline(start, 0)).to eq(start)
    end

    it 'returns nil for blank inputs' do
      expect(calculator.deadline(nil, 60)).to be_nil
      expect(calculator.deadline(brt('2026-09-02 10:00'), nil)).to be_nil
    end

    it 'preserves the sub-second part of the start time' do
      start = brt('2026-09-02 10:00:00.75')

      expect(calculator.deadline(start, 60)).to eq(start + 60.seconds)
    end

    context 'with several blocks in the same day' do
      let(:schedule) { create(:crm_service_schedule, account: account, weekdays: [3], hours: [['09:00', '12:00'], ['14:00', '18:00']]) }

      it 'jumps over the gap between blocks' do
        expect(calculator.deadline(brt('2026-09-02 11:45'), 30.minutes)).to eq(brt('2026-09-02 14:15'))
      end

      it 'starts at the next block when the start falls inside the gap' do
        expect(calculator.deadline(brt('2026-09-02 13:00'), 30.minutes)).to eq(brt('2026-09-02 14:30'))
      end

      it 'wraps to the same weekday next week when only one weekday is open' do
        expect(calculator.deadline(brt('2026-09-02 17:30'), 1.hour)).to eq(brt('2026-09-09 09:30'))
      end
    end

    context 'when the start time is in another timezone' do
      it 'interprets the schedule in its own timezone' do
        start_utc = Time.utc(2026, 9, 2, 16, 0) # 13:00 in Sao Paulo

        expect(calculator.deadline(start_utc, 30.minutes)).to eq(brt('2026-09-02 13:30'))
      end
    end

    context 'when the threshold is not reachable within MAX_DAYS' do
      let(:schedule) { create(:crm_service_schedule, account: account, weekdays: [3], hours: [['09:00', '09:01']]) }

      it 'returns nil instead of a bogus date' do
        expect(calculator.deadline(brt('2026-09-02 10:00'), 30.days)).to be_nil
      end
    end

    it 'is the inverse of #elapsed_seconds' do
      schedule = create(:crm_service_schedule, account: account, weekdays: [1, 3, 5], hours: [['08:00', '11:30'], ['13:00', '17:00']])
      calculator = described_class.new(schedule: schedule)
      starts = [brt('2026-09-02 07:00'), brt('2026-09-02 11:29'), brt('2026-09-04 16:59'), brt('2026-09-06 12:00')]

      starts.product([60, 30.minutes.to_i, 5.hours.to_i, 3.days.to_i]).each do |start, threshold|
        deadline = calculator.deadline(start, threshold)

        expect(calculator.elapsed_seconds(start, deadline)).to eq(threshold), "#{start} + #{threshold}s -> #{deadline}"
      end
    end
  end
end
