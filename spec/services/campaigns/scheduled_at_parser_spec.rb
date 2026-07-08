require 'rails_helper'

RSpec.describe Campaigns::ScheduledAtParser do
  let(:account) { create(:account) }

  describe '.call' do
    context 'with a naive local-time string for a BR account' do
      before { account.update!(reporting_timezone: 'America/Sao_Paulo') }

      it 'interprets the wall clock in the operational zone, not UTC' do
        with_modified_env DEFAULT_OPERATIONAL_TIMEZONE: nil do
          result = described_class.call(value: '2026-07-10 09:00', account: account)

          # 09:00 in America/Sao_Paulo (UTC-3) is 12:00 UTC — NOT 09:00 UTC.
          expect(result.utc.strftime('%Y-%m-%d %H:%M')).to eq('2026-07-10 12:00')
        end
      end

      it 'does not collapse to a UTC-shifted instant' do
        with_modified_env DEFAULT_OPERATIONAL_TIMEZONE: nil do
          result = described_class.call(value: '2026-07-10 09:00', account: account)

          expect(result.utc.hour).not_to eq(9)
        end
      end
    end

    context 'with a naive string and no resolvable operational timezone' do
      it 'fails closed with NaiveWithoutZoneError' do
        with_modified_env DEFAULT_OPERATIONAL_TIMEZONE: nil do
          expect do
            described_class.call(value: '2026-07-10 09:00', account: account)
          end.to raise_error(described_class::NaiveWithoutZoneError)
        end
      end
    end

    context 'with a naive string and only the ENV operational default configured' do
      it 'interprets the wall clock in the ENV default zone' do
        with_modified_env DEFAULT_OPERATIONAL_TIMEZONE: 'America/Sao_Paulo' do
          result = described_class.call(value: '2026-07-10 09:00', account: account)

          expect(result.utc.strftime('%Y-%m-%d %H:%M')).to eq('2026-07-10 12:00')
        end
      end
    end

    context 'with a string that already carries an offset' do
      before { account.update!(reporting_timezone: 'America/Sao_Paulo') }

      it 'honors the explicit offset regardless of operational zone' do
        result = described_class.call(value: '2026-07-10T09:00:00-03:00', account: account)

        expect(result.utc.strftime('%Y-%m-%d %H:%M')).to eq('2026-07-10 12:00')
      end

      it 'honors an explicit Z (UTC) offset as-is' do
        result = described_class.call(value: '2026-07-10T09:00:00Z', account: account)

        expect(result.utc.strftime('%Y-%m-%d %H:%M')).to eq('2026-07-10 09:00')
      end
    end

    context 'with an already-zoned Time object' do
      it 'returns it unchanged (absolute instant preserved)' do
        instant = 2.days.from_now

        expect(described_class.call(value: instant, account: account)).to eq(instant)
      end
    end

    context 'with a blank value' do
      it 'raises InvalidError' do
        expect do
          described_class.call(value: '', account: account)
        end.to raise_error(described_class::InvalidError)
      end
    end

    context 'when the inbox carries a genuine non-UTC operational zone' do
      let(:inbox) { create(:inbox, account: account, timezone: 'Australia/Sydney') }

      it 'interprets a naive string in the inbox zone' do
        with_modified_env DEFAULT_OPERATIONAL_TIMEZONE: nil do
          result = described_class.call(value: '2026-07-10 09:00', account: account, inbox: inbox)

          # 09:00 in Australia/Sydney (UTC+10, no DST in July) is 23:00 UTC on 2026-07-09.
          expect(result.utc.strftime('%Y-%m-%d %H:%M')).to eq('2026-07-09 23:00')
        end
      end
    end
  end
end
