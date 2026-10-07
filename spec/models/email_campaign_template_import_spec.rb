require 'rails_helper'

# Importar modelo (#1099, entrega B): a trava de uma importação ativa por conta, que expira em 120 s, e a retomada de
# um job morto.
RSpec.describe EmailCampaignTemplateImport, :aggregate_failures do
  let(:account) { create(:account) }

  def build_import(**attrs)
    described_class.create!({ account: account, source_kind: 'paste' }.merge(attrs))
  end

  it 'starts queued, locked for 120 seconds and expiring in 7 days' do
    freeze_time do
      import = build_import

      expect(import.status).to eq('queued')
      expect(import.locked_until).to eq(120.seconds.from_now)
      expect(import.expires_at).to eq(7.days.from_now)
    end
  end

  it 'refuses a second active import in the same account at the database level' do
    build_import

    expect { build_import }.to raise_error(ActiveRecord::RecordNotUnique)
    expect { described_class.create!(account: create(:account), source_kind: 'paste') }.not_to raise_error
  end

  it 'accepts a new import once the previous one finished' do
    first = build_import
    first.update!(status: 'failed', error_code: 'internal')

    expect { build_import }.not_to raise_error
  end

  it 'validates the kind of source and the status' do
    expect(described_class.new(account: account, source_kind: 'ftp')).not_to be_valid
    expect(described_class.new(account: account, source_kind: 'paste', status: 'other')).not_to be_valid
  end

  describe '#claim!' do
    it 'lets one worker take a queued import and returns the attempt as its token' do
      import = build_import

      token = import.claim!

      expect(token).to eq(1)
      expect(import.reload.status).to eq('processing')
      expect(import.claim!).to be_nil
    end

    it 'lets a worker take back an import whose lock expired (dead job)' do
      import = build_import
      import.claim!

      travel 121.seconds do
        expect(import.claim!).to eq(2)
      end
    end

    it 'does not take a finished import' do
      import = build_import
      import.update!(status: 'ready')

      expect(import.claim!).to be_nil
    end
  end

  describe 'writes guarded by the token' do
    it 'ignores the result of a worker that lost the import' do
      import = build_import
      old_token = import.claim!
      travel 121.seconds
      new_token = import.claim!

      expect(import.finish!(old_token, mjml: '<mjml></mjml>', report: {})).to be(false)
      expect(import.finish!(new_token, mjml: '<mjml>ok</mjml>', report: { 'version' => 1 })).to be(true)
      expect(import.reload).to have_attributes(status: 'ready', result_mjml: '<mjml>ok</mjml>', locked_until: nil)
      expect(import.fail!(new_token, :internal)).to be(false)
    end

    it 'records the failure code' do
      import = build_import
      token = import.claim!

      expect(import.fail!(token, :zip_unsafe_path)).to be(true)
      expect(import.reload).to have_attributes(status: 'failed', error_code: 'zip_unsafe_path', locked_until: nil)
    end
  end

  describe '#recover_if_stalled!' do
    it 'does nothing while the lock holds' do
      import = build_import

      expect(import.recover_if_stalled!).to eq(:running)
      expect(import.reload.status).to eq('queued')
    end

    it 'queues a dead job again while attempts are left' do
      import = build_import
      import.claim!

      travel 121.seconds do
        expect(import.recover_if_stalled!).to eq(:resumed)
        expect(import.reload).to have_attributes(status: 'queued', locked_until: 120.seconds.from_now)
      end
    end

    it 'gives up after the last attempt, freeing the account' do
      import = build_import
      import.claim!
      travel 121.seconds
      import.claim!
      travel 121.seconds

      expect(import.recover_if_stalled!).to eq(:failed)
      expect(import.reload).to have_attributes(status: 'failed', error_code: 'stalled')
      expect { build_import }.not_to raise_error
    end
  end

  describe '.expired' do
    it 'lists imports past their expiry that were never saved' do
      old = build_import
      old.update!(status: 'ready', expires_at: 1.minute.ago)
      saved = described_class.create!(account: create(:account), source_kind: 'paste', status: 'saved', expires_at: 1.minute.ago)

      expect(described_class.expired).to contain_exactly(old)
      expect(described_class.expired).not_to include(saved)
    end
  end
end
