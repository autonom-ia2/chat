require 'rails_helper'

RSpec.describe BrandImportJob do
  let(:account) { create(:account) }

  it 'allows a single queued or running import per account' do
    create(:brand_import_job, account: account, status: :running)

    expect { create(:brand_import_job, account: account) }.to raise_error(ActiveRecord::RecordNotUnique)
    expect(create(:brand_import_job, status: :queued)).to be_persisted
  end

  it 'allows a new import once the previous one finished' do
    create(:brand_import_job, account: account, status: :succeeded)
    create(:brand_import_job, account: account, status: :failed)

    expect(create(:brand_import_job, account: account)).to be_queued
  end

  it 'treats an active import older than the stale window as stale' do
    job = create(:brand_import_job, account: account, status: :running, created_at: 10.minutes.ago)

    expect(job).to be_stale
    expect(create(:brand_import_job, status: :running)).not_to be_stale
  end
end
