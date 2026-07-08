require 'rails_helper'

# H4-booking: a booking profile's `timezone` anchors every public slot. A
# garbage value used to silently collapse to UTC. We now (a) reject a non-IANA
# timezone at the model boundary and (b) resolve the operational zone through the
# shared TimeZoneResolver, reporting :none (fail-closed) when nothing resolves.
RSpec.describe Crm::AgentBookingProfile do
  def timezone_errors(value)
    profile = described_class.new(timezone: value)
    profile.valid?
    profile.errors[:timezone]
  end

  describe 'timezone IANA validation' do
    it 'rejects a non-IANA timezone string' do
      expect(timezone_errors('Totally/Bogus')).to be_present
    end

    it 'accepts a valid IANA timezone' do
      expect(timezone_errors('America/Sao_Paulo')).to be_empty
    end

    it 'allows a blank timezone (resolution then falls through to account/ENV)' do
      expect(timezone_errors(nil)).to be_empty
    end
  end

  describe '#timezone_resolution' do
    it 'honors a valid profile timezone as the primary source' do
      account = instance_double(Account, reporting_timezone: nil)
      profile = described_class.new(timezone: 'America/Sao_Paulo')
      allow(profile).to receive_messages(account: account, inbox: nil)

      resolution = profile.timezone_resolution

      expect(resolution.resolved?).to be(true)
      expect(resolution.zone.name).to eq('America/Sao_Paulo')
    end

    it 'falls through to the account operational timezone when profile tz is blank' do
      account = instance_double(Account, reporting_timezone: 'America/Sao_Paulo')
      profile = described_class.new(timezone: nil)
      allow(profile).to receive_messages(account: account, inbox: nil)

      resolution = profile.timezone_resolution

      expect(resolution.source).to eq(:account)
      expect(resolution.zone.name).to eq('America/Sao_Paulo')
    end

    it 'reports :none (fail-closed) when nothing resolves' do
      account = instance_double(Account, reporting_timezone: nil)
      profile = described_class.new(timezone: nil)
      allow(profile).to receive_messages(account: account, inbox: nil)

      with_modified_env DEFAULT_OPERATIONAL_TIMEZONE: nil do
        resolution = profile.timezone_resolution
        expect(resolution.resolved?).to be(false)
        expect(resolution.source).to eq(:none)
      end
    end
  end
end
