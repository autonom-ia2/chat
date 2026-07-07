require 'rails_helper'

RSpec.describe TimeZoneResolver do
  # Lightweight stand-ins: the resolver only reads a couple of duck-typed
  # methods, so we avoid DB/factory overhead for this pure unit.
  def contact_with(tz_name)
    instance_double(Contact, additional_attributes: { 'timezone' => tz_name })
  end

  def account_with(tz_name)
    instance_double(Account, reporting_timezone: tz_name)
  end

  describe '.for chain order' do
    it 'prefers the contact timezone over account and ENV' do
      with_modified_env DEFAULT_OPERATIONAL_TIMEZONE: 'Europe/Lisbon' do
        result = described_class.for(
          contact: contact_with('America/Sao_Paulo'),
          account: account_with('America/New_York')
        )

        expect(result.source).to eq(:contact)
        expect(result.zone.name).to eq('America/Sao_Paulo')
        expect(result.resolved?).to be(true)
      end
    end

    it 'falls back to account.reporting_timezone when contact has none' do
      with_modified_env DEFAULT_OPERATIONAL_TIMEZONE: 'Europe/Lisbon' do
        result = described_class.for(
          contact: contact_with(nil),
          account: account_with('America/New_York')
        )

        expect(result.source).to eq(:account)
        expect(result.zone.name).to eq('America/New_York')
      end
    end

    it 'falls back to ENV default when contact and account have none' do
      with_modified_env DEFAULT_OPERATIONAL_TIMEZONE: 'America/Sao_Paulo' do
        result = described_class.for(
          contact: contact_with(nil),
          account: account_with(nil)
        )

        expect(result.source).to eq(:default)
        expect(result.zone.name).to eq('America/Sao_Paulo')
      end
    end
  end

  describe 'invalid timezone values are ignored' do
    it 'skips an invalid contact tz and uses the next valid source' do
      with_modified_env DEFAULT_OPERATIONAL_TIMEZONE: nil do
        result = described_class.for(
          contact: contact_with('Not/AZone'),
          account: account_with('America/New_York')
        )

        expect(result.source).to eq(:account)
        expect(result.zone.name).to eq('America/New_York')
      end
    end

    it 'skips an invalid account tz and uses the ENV default' do
      with_modified_env DEFAULT_OPERATIONAL_TIMEZONE: 'America/Sao_Paulo' do
        result = described_class.for(
          contact: contact_with(nil),
          account: account_with('Totally/Bogus')
        )

        expect(result.source).to eq(:default)
        expect(result.zone.name).to eq('America/Sao_Paulo')
      end
    end

    it 'ignores an invalid ENV default and reports :none' do
      with_modified_env DEFAULT_OPERATIONAL_TIMEZONE: 'Bad/Zone' do
        result = described_class.for(
          contact: contact_with(nil),
          account: account_with(nil)
        )

        expect(result.source).to eq(:none)
        expect(result.zone.name).to eq('UTC')
      end
    end
  end

  describe 'fail-closed :none' do
    it 'returns UTC with source :none when nothing resolves' do
      with_modified_env DEFAULT_OPERATIONAL_TIMEZONE: nil do
        result = described_class.for(
          contact: contact_with(nil),
          account: account_with(nil)
        )

        expect(result.source).to eq(:none)
        expect(result.zone).to eq(ActiveSupport::TimeZone['UTC'])
        expect(result.resolved?).to be(false)
      end
    end

    it 'returns :none when called with no arguments and no ENV default' do
      with_modified_env DEFAULT_OPERATIONAL_TIMEZONE: nil do
        result = described_class.for

        expect(result.source).to eq(:none)
        expect(result.zone.name).to eq('UTC')
      end
    end
  end

  describe '.zone_for' do
    it 'returns just the zone from the resolved source' do
      with_modified_env DEFAULT_OPERATIONAL_TIMEZONE: nil do
        zone = described_class.zone_for(contact: contact_with('America/Sao_Paulo'))

        expect(zone).to be_a(ActiveSupport::TimeZone)
        expect(zone.name).to eq('America/Sao_Paulo')
      end
    end

    it 'never returns nil, falling back to UTC' do
      with_modified_env DEFAULT_OPERATIONAL_TIMEZONE: nil do
        expect(described_class.zone_for.name).to eq('UTC')
      end
    end
  end

  describe 'ENV DEFAULT_OPERATIONAL_TIMEZONE respected' do
    it 'uses the configured ENV default and does not hardcode any region' do
      with_modified_env DEFAULT_OPERATIONAL_TIMEZONE: 'Asia/Tokyo' do
        result = described_class.for

        expect(result.source).to eq(:default)
        expect(result.zone.name).to eq('Asia/Tokyo')
      end
    end
  end
end
