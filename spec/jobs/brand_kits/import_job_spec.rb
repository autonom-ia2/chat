require 'rails_helper'

RSpec.describe BrandKits::ImportJob do
  let(:job) { create(:brand_import_job) }
  let(:proposal) { { 'name' => 'Hub2You', 'appearance' => {}, 'warnings' => [] } }

  it 'runs the import and stores the proposal' do
    importer = instance_double(BrandKits::SiteImporter, perform: proposal)
    allow(BrandKits::SiteImporter).to receive(:new).with('https://hub2you.ai/').and_return(importer)

    described_class.perform_now(job.id)

    expect(job.reload).to be_succeeded
    expect(job.result).to eq(proposal)
    expect(job.started_at).to be_present
    expect(job.finished_at).to be_present
  end

  it 'marks the import as failed with the importer error code' do
    allow(BrandKits::SiteImporter).to receive(:new).and_raise(BrandKits::SiteImporter::Error.new('unsafe_url'))

    described_class.perform_now(job.id)

    expect(job.reload).to be_failed
    expect(job.error_code).to eq('unsafe_url')
  end

  it 'marks unexpected errors as internal_error without retrying forever' do
    allow(BrandKits::SiteImporter).to receive(:new).and_raise(NoMethodError)

    described_class.perform_now(job.id)

    expect(job.reload.error_code).to eq('internal_error')
  end

  it 'does nothing for an import that is no longer queued' do
    job.update!(status: :failed, error_code: 'stale')
    allow(BrandKits::SiteImporter).to receive(:new)

    described_class.perform_now(job.id)

    expect(BrandKits::SiteImporter).not_to have_received(:new)
  end
end
