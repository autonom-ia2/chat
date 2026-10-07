require 'rails_helper'

RSpec.describe Crm::MetaAdvisorAction do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:today) { Date.new(2026, 10, 7) }

  def create_action(attrs = {})
    described_class.create!({ account: account, local_date: today, kind: 'stalled_quotes', subject_key: 'account',
                              position: 1 }.merge(attrs))
  end

  describe 'validations' do
    it 'accepts only the 7 persisted kinds (fillers never become a row)' do
      expect(described_class.new(account: account, local_date: today, kind: 'wait', subject_key: 'account', position: 1))
        .not_to be_valid
    end

    it 'accepts only panel or api as the origin of a gesture' do
      action = create_action

      expect { action.open!(user, via: 'whatsapp') }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it 'keeps one row per account, day, kind and subject' do
      create_action

      expect { create_action(position: 2) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe '#open!' do
    it 'records who opened, when and from where, without changing the status' do
      action = create_action

      action.open!(user, via: 'panel')

      expect(action.reload).to have_attributes(status: 'open', opened_by: user, opened_via: 'panel')
      expect(action.opened_at).to be_present
    end

    it 'is idempotent: a second click keeps the first record' do
      action = create_action
      action.open!(user, via: 'panel')
      first_opened_at = action.reload.opened_at
      other = create(:user, account: account, role: :administrator)

      travel 1.hour do
        action.open!(other, via: 'api')
      end

      expect(action.reload).to have_attributes(opened_at: first_opened_at, opened_by: user, opened_via: 'panel')
    end

    it 'works on an action that is no longer open' do
      action = create_action(status: :accepted)

      action.open!(user, via: 'panel')

      expect(action.reload).to have_attributes(status: 'accepted', opened_by: user)
    end
  end

  describe '#accept! and #dismiss!' do
    it 'accepts an open action and records the resolution' do
      action = create_action

      action.accept!(user, via: 'panel')

      expect(action.reload).to have_attributes(status: 'accepted', resolved_by: user, resolved_via: 'panel')
      expect(action.resolved_at).to be_present
    end

    it 'dismisses an open action and records the resolution' do
      action = create_action

      action.dismiss!(user, via: 'api')

      expect(action.reload).to have_attributes(status: 'dismissed', resolved_by: user, resolved_via: 'api')
    end

    it 'refuses to resolve an action that is not open' do
      accepted = create_action(status: :accepted)
      dismissed = create_action(kind: 'fix_tracking', status: :dismissed)
      expired = create_action(kind: 'slow_response', status: :expired)

      expect { accepted.dismiss!(user, via: 'panel') }.to raise_error(described_class::NotOpen)
      expect { dismissed.accept!(user, via: 'panel') }.to raise_error(described_class::NotOpen)
      expect { expired.accept!(user, via: 'panel') }.to raise_error(described_class::NotOpen)
      expect(accepted.reload.status).to eq('accepted')
    end

    it 'reads the current status from the database, not from a stale copy' do
      action = create_action
      described_class.find(action.id).dismiss!(user, via: 'panel')

      expect { action.accept!(user, via: 'panel') }.to raise_error(described_class::NotOpen)
      expect(action.reload.status).to eq('dismissed')
    end
  end

  describe '.acceptance' do
    let(:from) { today - 14 }
    let(:to) { today - 1 }
    let(:shown_at) { Time.zone.parse('2026-10-05 12:00') }

    def shown_action(kind, attrs = {})
      create_action({ kind: kind, local_date: today - 2, shown_at: shown_at }.merge(attrs))
    end

    it 'counts expired and still-open actions against the rate and leaves the Guide out' do
      shown_action('stalled_quotes', status: :accepted, resolved_via: 'panel', opened_at: shown_at)
      shown_action('slow_response', status: :accepted, resolved_via: 'panel')
      shown_action('fix_tracking', status: :dismissed, resolved_via: 'panel')
      shown_action('review_ad', status: :expired, opened_at: shown_at)
      shown_action('scale_ad', status: :open)
      shown_action('auction_pressure', status: :accepted, resolved_via: 'api')

      expect(described_class.acceptance(account.id, from: from, to: to))
        .to eq(shown: 5, opened: 2, accepted: 2, dismissed: 1, unanswered: 2, rate: 0.4)
    end

    it 'ignores actions never shown, outside the period or from another account' do
      shown_action('stalled_quotes', status: :accepted, resolved_via: 'panel')
      shown_action('slow_response', shown_at: nil)
      shown_action('fix_tracking', local_date: today)
      described_class.create!(account: create(:account), local_date: today - 2, kind: 'review_ad', subject_key: 'ad:1',
                              position: 1, shown_at: shown_at)

      expect(described_class.acceptance(account.id, from: from, to: to))
        .to eq(shown: 1, opened: 0, accepted: 1, dismissed: 0, unanswered: 0, rate: 1.0)
    end

    it 'returns a nil rate without any action in the denominator' do
      expect(described_class.acceptance(account.id, from: from, to: to))
        .to eq(shown: 0, opened: 0, accepted: 0, dismissed: 0, unanswered: 0, rate: nil)
    end
  end

  describe 'runs' do
    it 'keeps the action when its run is deleted (actions outlive runs)' do
      run = Crm::MetaAdvisorRun.create!(account: account, ad_account_id: 'act_1', local_date: today, locale: 'pt_BR',
                                        signature: 'a' * 64, rules_version: 'f5.1', trigger: 'panel')
      action = create_action(run: run, last_run_id: run.id)

      run.delete

      expect(action.reload).to have_attributes(run_id: nil, last_run_id: nil)
    end
  end
end
