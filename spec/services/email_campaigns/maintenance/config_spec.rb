require 'rails_helper'

RSpec.describe EmailCampaigns::Maintenance::Config do
  it 'is disabled unless the flag is the exact string true' do
    expect(described_class.new({})).not_to be_apply_enabled
    expect(described_class.new('EMAIL_CAMPAIGN_PROTECTION_BACKFILL_ENABLED' => 'false')).not_to be_apply_enabled
    expect(described_class.new('EMAIL_CAMPAIGN_PROTECTION_BACKFILL_ENABLED' => 'true')).to be_apply_enabled
  end

  it 'rejects malformed configuration rather than treating it as truthy' do
    [true, false, nil, '1', '', 'TRUE', 'yes'].each do |value|
      expect { described_class.new('EMAIL_CAMPAIGN_PROTECTION_BACKFILL_ENABLED' => value) }
        .to raise_error(described_class::Invalid, 'invalid_backfill_configuration')
    end
  end
end
