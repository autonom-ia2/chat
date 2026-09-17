require 'rails_helper'

RSpec.describe EmailCampaigns::Maintenance::Start do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, type: 'SuperAdmin').becomes(SuperAdmin) }
  let(:parameters) { { reason: 'epic436 reviewed', idempotency_key: 'epic436_apply_01', mode: 'apply', confirm: 'apply' } }
  let(:enabled) { EmailCampaigns::Maintenance::Config.new('EMAIL_CAMPAIGN_PROTECTION_BACKFILL_ENABLED' => 'true') }
  let(:disabled) { EmailCampaigns::Maintenance::Config.new({}) }

  it 'requires a persisted platform administrator, including for dry run' do
    [create(:user, account: account, role: :administrator), SuperAdmin.new].each do |user|
      expect { described_class.call(account: account, actor: user, parameters: parameters, config: enabled) }
        .to raise_error(Pundit::NotAuthorizedError)
    end
    actor.update!(type: nil)
    expect { described_class.call(account: account, actor: actor, parameters: parameters, config: enabled) }
      .to raise_error(Pundit::NotAuthorizedError)
  end

  it 'does not create an apply run with the flag disabled' do
    expect { described_class.call(account: account, actor: actor, parameters: parameters, config: disabled) }
      .to raise_error(EmailCampaigns::Maintenance::Request::Invalid, 'apply_disabled')
    expect(EmailProtectionMaintenanceRun.count).to eq(0)
  end

  it 'creates only one run per tenant and key and rejects conflicting reuse' do
    first = described_class.call(account: account, actor: actor, parameters: parameters, config: enabled)
    second = described_class.call(account: account, actor: actor, parameters: parameters, config: enabled)
    expect(second.id).to eq(first.id)
    expect(EmailProtectionMaintenanceRun.count).to eq(1)
    expect { described_class.call(account: account, actor: actor, parameters: parameters.except(:confirm).merge(mode: 'dry_run'), config: enabled) }
      .to raise_error(EmailCampaigns::Maintenance::Request::Invalid, 'idempotency_conflict')
  end

  it 'does not dispatch until the enclosing transaction commits' do
    expect do
      EmailProtectionMaintenanceRun.transaction do
        described_class.call(account: account, actor: actor, parameters: parameters, config: enabled)
        expect(enqueued_jobs).to be_empty
        raise ActiveRecord::Rollback
      end
    end.not_to change(EmailProtectionMaintenanceRun, :count)
    expect(enqueued_jobs).to be_empty
  end

  it 'dispatches after an enclosing commit even though Start reloads the returned run' do
    run = nil
    expect do
      EmailProtectionMaintenanceRun.transaction do
        run = described_class.call(account: account, actor: actor, parameters: parameters, config: enabled)
        expect(enqueued_jobs).to be_empty
      end
    end.to have_enqueued_job(EmailCampaigns::ProtectionBackfillJob)
    expect(run.reload.enqueue_attempts).to eq(1)
  end

  it 'uses the persisted type as authority even if the Ruby instance was loaded as User' do
    persisted = actor.becomes(User)
    expect(described_class.call(account: account, actor: persisted, parameters: parameters, config: enabled)).to be_persisted
    ordinary = create(:user, account: account).becomes(SuperAdmin)
    expect { described_class.call(account: account, actor: ordinary, parameters: parameters, config: enabled) }
      .to raise_error(Pundit::NotAuthorizedError)
  end

  it 'checks current membership and account status even when invoked without a controller' do
    actor.account_users.where(account: account).delete_all
    expect { described_class.call(account: account, actor: actor, parameters: parameters, config: enabled) }
      .to raise_error(Pundit::NotAuthorizedError)
    create(:account_user, account: account, user: actor)
    account.update!(status: :suspended)
    expect { described_class.call(account: account, actor: actor, parameters: parameters, config: enabled) }
      .to raise_error(Pundit::NotAuthorizedError)
    expect(EmailProtectionMaintenanceRun.count).to eq(0)
  end
end
