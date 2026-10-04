require 'rails_helper'

RSpec.describe Instagram::Automation::AccountRollout do
  subject(:rollout) { described_class.new }

  let!(:account) { create(:account, internal_attributes: { 'unrelated' => 'preserved' }) }
  let(:feature) { described_class::FEATURE }
  let(:marker) { described_class::MARKER }

  before do
    account.enable_features('channel_instagram', 'labels')
    account.disable_features(feature)
    account.save!
  end

  it 'defaults to a read-only preview without setting the flag or marker' do
    expect(rollout.call[:would_enable]).to eq(1)
    expect(account.reload.feature_enabled?(feature)).to be false
    expect(account.internal_attributes).to eq('unrelated' => 'preserved')
  end

  it 'requires exact confirmation before reading accounts' do
    expect(Account).not_to receive(:find_each)
    [nil, '', 'true', 'INSTAGRAM_ASSISTED_ONBOARDING'].each do |confirmation|
      expect { rollout.call(dry_run: false, confirmation: confirmation) }.to raise_error(ArgumentError)
    end
  end

  it 'persists the flag and marker together without changing other bits or attributes' do
    previous_bits = account.feature_flags
    expect(rollout.call(dry_run: false, confirmation: feature)[:enabled]).to eq(1)
    expect(account.reload.feature_enabled?(feature)).to be true
    expect(account.feature_flags).to eq(previous_bits)
    expect(account.internal_attributes).to eq('unrelated' => 'preserved', marker => true)
  end

  it 'does not grant the Instagram channel to an ineligible account' do
    account.disable_features!('channel_instagram')
    expect(rollout.call(dry_run: false, confirmation: feature)[:ineligible]).to eq(1)
    expect(account.reload.feature_enabled?('channel_instagram')).to be false
    expect(account.feature_enabled?(feature)).to be false
    expect(account.internal_attributes).not_to have_key(marker)
  end

  it 'preserves a manual OFF marked before the first application' do
    account.update!(internal_attributes: account.internal_attributes.merge(marker => true))
    expect(rollout.call[:processed]).to eq(1)
    expect(rollout.call(dry_run: false, confirmation: feature)[:processed]).to eq(1)
    expect(account.reload.feature_enabled?(feature)).to be false
  end

  it 'is idempotent and preserves OFF between executions' do
    rollout.call(dry_run: false, confirmation: feature)
    account.reload.disable_features!(feature)
    expect(rollout.call[:processed]).to eq(1)
    expect(rollout.call(dry_run: false, confirmation: feature)[:processed]).to eq(1)
    expect(account.reload.feature_enabled?(feature)).to be false
  end

  it 'marks already-enabled accounts too and preserves their subsequent OFF' do
    account.enable_features!(feature)
    expect(rollout.call[:already_enabled]).to eq(1)
    expect(account.reload.internal_attributes).not_to have_key(marker)
    expect(rollout.call(dry_run: false, confirmation: feature)[:already_enabled]).to eq(1)
    account.reload.disable_features!(feature)
    expect(rollout.call(dry_run: false, confirmation: feature)[:processed]).to eq(1)
    expect(account.reload.feature_enabled?(feature)).to be false
  end

  it 'reloads the marker under the real account lock before applying' do
    allow(Account).to receive(:find_each).and_yield(account)
    Account.find(account.id).update!(internal_attributes: account.internal_attributes.merge(marker => true))
    expect(rollout.call(dry_run: false, confirmation: feature)[:processed]).to eq(1)
    expect(account.reload.feature_enabled?(feature)).to be false
  end

  it 'rolls back both the bit and marker if saving fails' do
    allow(Account).to receive(:find_each).and_yield(account)
    allow(account).to receive(:save!).and_wrap_original do |original, *args|
      original.call(*args)
      raise ActiveRecord::RecordInvalid, account
    end
    expect { rollout.call(dry_run: false, confirmation: feature) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(account.reload.feature_enabled?(feature)).to be false
    expect(account.internal_attributes).not_to have_key(marker)
  end
end
