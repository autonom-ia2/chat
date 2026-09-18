require 'rails_helper'

RSpec.describe EmailCampaigns::Maintenance::Request do
  let(:parameters) { { reason: 'Reviewed epic436 preview', idempotency_key: 'epic436_preview' } }

  it 'defaults to a bounded dry run' do
    expect(described_class.new(parameters).attributes).to include(dry_run: true, batch_size: 100)
  end

  it 'requires exact apply and validates all writable parameters' do
    [{ mode: true }, { mode: false }, { mode: nil }, { mode: :apply }, { mode: 'APPLY' }, { mode: 'apply ' },
     { mode: ' apply' }, { reason: '' }, { reason: 'x' * 201 }, { reason: [] },
     { idempotency_key: 'short' }, { idempotency_key: 'x' * 101 }, { idempotency_key: {} },
     { batch_size: 501 }, { batch_size: 0 }, { batch_size: '1.5' }, { batch_size: [] },
     { account_id: 123 }, { kind: 'release' }, { provider: 'ses' }, { actor_id: 1 }, { dry_run: false }].each do |invalid|
      expect { described_class.new(parameters.merge(invalid)) }.to raise_error(EmailCampaigns::Maintenance::Request::Invalid)
    end
  end

  it 'accepts the maximum batch size without truthiness conversions' do
    input = parameters.merge(mode: 'apply', confirm: 'apply', batch_size: '500')
    expect(described_class.new(input).attributes).to include(dry_run: false, batch_size: 500)
  end

  it 'requires a separate exact confirmation for apply and rejects confirmation on previews' do
    [nil, true, false, 'true', 'APPLY', ' apply', 'apply ', :apply].each do |confirm|
      expect { described_class.new(parameters.merge(mode: 'apply', confirm: confirm)) }
        .to raise_error(EmailCampaigns::Maintenance::Request::Invalid, 'invalid_confirm')
    end
    expect { described_class.new(parameters.merge(mode: 'apply')) }
      .to raise_error(EmailCampaigns::Maintenance::Request::Invalid, 'invalid_confirm')
    expect { described_class.new(parameters.merge(confirm: 'apply')) }
      .to raise_error(EmailCampaigns::Maintenance::Request::Invalid, 'invalid_confirm')
  end
end
