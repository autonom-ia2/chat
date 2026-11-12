require 'rails_helper'

# #2921: an import left `importing` by a worker that died, or left `queued` with no job, is put back in the queue and
# ends by itself. An import that is still moving, or that is in any other status, is never touched.
RSpec.describe CampaignImports::StalledImportsJob, :aggregate_failures, type: :job do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  let(:stall) { CampaignImports::Config.stalled_import_after }
  let(:gate) { 'true' }

  around do |example|
    with_modified_env('CAMPAIGN_IMPORT_ENABLED' => gate) { example.run }
  end

  before { stub_const('CampaignImports::Importer::BLOCK_SIZE', 2) }

  # The worker died on the second of three blocks: two people saved, three to go, status `importing`.
  def stuck_import(flow = :contacts)
    kill_import_on_block(queued_import(flow, account: account, user: user), 2)
  end

  # "Confirmar" (or an earlier sweep) committed `queued` and the import job never reached the queue.
  def orphan_queued(queued_at:)
    queued_import(:contacts, account: account, user: user).tap { |campaign_import| campaign_import.update!(queued_at: queued_at) }
  end

  def age_import(campaign_import, moved_at)
    campaign_import.update_columns(updated_at: moved_at) # rubocop:disable Rails/SkipsModelValidations
  end

  def age_rows(campaign_import, moved_at)
    campaign_import.campaign_import_rows.update_all(updated_at: moved_at) # rubocop:disable Rails/SkipsModelValidations
  end

  def sweep
    described_class.perform_now
  end

  CampaignImportResumeHelpers::FLOWS.each do |flow|
    context "with the #{flow} flow" do
      it 'ends by itself, with every valid row imported once, after nothing moved for the stall time' do
        campaign_import = stuck_import(flow)
        expect(campaign_import).to be_importing
        expect(campaign_import.campaign_import_rows.status_imported.count).to eq(2)

        travel_to(stall.from_now + 1.minute) { perform_enqueued_jobs { sweep } }

        campaign_import.reload
        expect(campaign_import).to be_completed
        expect(campaign_import).to have_attributes(imported_contacts_count: 5, existing_contacts_count: 0, failed_contacts_count: 0)
        expect(account.contacts.pluck(:phone_number)).to match_array(resume_phones)
        expect(campaign_import.campaign_import_rows.status_imported.pluck(:contact_id)).to match_array(account.contacts.pluck(:id))
      end
    end
  end

  it 'puts the stalled import back in the queue with one import job, and a second sweep adds none' do
    campaign_import = stuck_import

    travel_to(stall.from_now + 1.minute) do
      expect { sweep }.to have_enqueued_job(CampaignImports::ImportJob).with(campaign_import).exactly(:once)
      expect(campaign_import.reload).to be_queued
      expect(campaign_import.queued_at).to be_within(1.second).of(Time.current)

      expect { sweep }.not_to have_enqueued_job(CampaignImports::ImportJob)
      expect(campaign_import.reload).to be_queued
    end
  end

  it 'goes on with an import whose worker died before writing any row' do
    campaign_import = kill_import_on_block(queued_import(:audience, account: account, user: user), 1)
    expect(campaign_import).to be_importing
    expect(campaign_import.campaign_import_rows.status_imported.count).to eq(0)

    travel_to(stall.from_now + 1.minute) { perform_enqueued_jobs { sweep } }

    expect(campaign_import.reload).to be_completed
    expect(account.contacts.pluck(:phone_number)).to match_array(resume_phones)
  end

  # The last move is the newest of the import's own `updated_at` (the Importer touches it after each block) and of its
  # rows' `updated_at`.
  describe 'the last move' do
    it 'puts back in the queue an import whose own last touch and rows are both older than the stall time' do
      campaign_import = stuck_import
      age_import(campaign_import, 2.hours.ago)
      age_rows(campaign_import, 2.hours.ago)

      expect { sweep }.to have_enqueued_job(CampaignImports::ImportJob).with(campaign_import).exactly(:once)
      expect(campaign_import.reload).to be_queued
    end

    it 'puts back in the queue an old stalled import that has no import_started_at' do
      campaign_import = stuck_import
      campaign_import.update_columns(import_started_at: nil, updated_at: 2.hours.ago) # rubocop:disable Rails/SkipsModelValidations
      age_rows(campaign_import, 2.hours.ago)

      expect { sweep }.to have_enqueued_job(CampaignImports::ImportJob).with(campaign_import).exactly(:once)
      expect(campaign_import.reload).to be_queued
    end

    it 'leaves alone an import that moved less than the stall time ago' do
      campaign_import = stuck_import

      travel_to(stall.from_now - 1.minute) do
        expect { sweep }.not_to have_enqueued_job(CampaignImports::ImportJob)
      end
      expect(campaign_import.reload).to be_importing
    end

    it 'leaves alone an import whose rows are old when the import itself was touched a moment ago' do
      campaign_import = stuck_import
      age_rows(campaign_import, 2.hours.ago)

      expect { sweep }.not_to have_enqueued_job(CampaignImports::ImportJob)
      expect(campaign_import.reload).to be_importing
    end

    it 'leaves alone an import last touched long ago when one of its rows moved a moment ago' do
      campaign_import = stuck_import
      age_import(campaign_import, 2.hours.ago)

      expect { sweep }.not_to have_enqueued_job(CampaignImports::ImportJob)
      expect(campaign_import.reload).to be_importing
    end
  end

  describe 'an import left queued with no job' do
    it 'gets one import job again and a new queued_at, and the sweep right after adds none' do
      campaign_import = orphan_queued(queued_at: (stall + 1.minute).ago)

      freeze_time do
        expect { sweep }.to have_enqueued_job(CampaignImports::ImportJob).with(campaign_import).exactly(:once)
        expect(campaign_import.reload).to be_queued
        expect(campaign_import.queued_at).to be_within(1.second).of(Time.current)

        expect { sweep }.not_to have_enqueued_job(CampaignImports::ImportJob)
      end
    end

    it 'ends by itself once the job runs' do
      campaign_import = orphan_queued(queued_at: (stall + 1.minute).ago)

      perform_enqueued_jobs { sweep }

      expect(campaign_import.reload).to be_completed
      expect(account.contacts.pluck(:phone_number)).to match_array(resume_phones)
    end

    it 'is left alone while it was queued less than the stall time ago' do
      queued_at = (stall - 1.minute).ago
      campaign_import = orphan_queued(queued_at: queued_at)

      expect { sweep }.not_to have_enqueued_job(CampaignImports::ImportJob)
      expect(campaign_import.reload.queued_at).to be_within(1.second).of(queued_at)
    end
  end

  it 'goes on to the next import when one of them raises, and logs only its id and the error class' do
    first = stuck_import
    second = stuck_import
    allow(CampaignImports::ImportJob).to receive(:perform_later).and_wrap_original do |original, campaign_import|
      raise 'fila fora do ar para 11987650001' if campaign_import.id == first.id

      original.call(campaign_import)
    end
    allow(Rails.logger).to receive(:error)

    travel_to(stall.from_now + 1.minute) do
      expect { sweep }.to have_enqueued_job(CampaignImports::ImportJob).with(second).exactly(:once)
    end

    expect(second.reload).to be_queued
    expect(first.reload).to be_queued # committed before the enqueue raised: an orphan a later sweep picks up
    expect(Rails.logger).to have_received(:error).with("[CampaignImports::StalledImportsJob] import_id=#{first.id} RuntimeError")
  end

  it 'leaves alone an import in any other status, however long ago it moved' do
    campaign_import = stuck_import

    travel_to(stall.from_now + 1.hour) do
      %w[uploaded ready_to_confirm completed completed_with_failures failed].each do |status|
        campaign_import.update!(status: status)
        age_import(campaign_import, 2.hours.ago)

        expect { sweep }.not_to have_enqueued_job(CampaignImports::ImportJob)
        expect(campaign_import.reload.status).to eq(status)
      end
    end
  end

  it 'leaves alone the imports of an automation step, which have no file to read again' do
    writing = automation_import(account: account, user: user, status: :importing, started_at: 2.hours.ago)
    age_import(writing, 2.hours.ago)
    waiting = automation_import(account: account, user: user, status: :queued, started_at: 2.hours.ago)
    waiting.update!(queued_at: 2.hours.ago)

    expect { sweep }.not_to have_enqueued_job(CampaignImports::ImportJob)
    expect(writing.reload).to be_importing
    expect(waiting.reload.queued_at).to be_within(1.second).of(2.hours.ago)
  end

  [nil, 'false'].each do |value|
    context "with CAMPAIGN_IMPORT_ENABLED #{value.nil? ? 'unset' : 'false'}" do
      let(:gate) { value }

      it 'does nothing' do
        stalled = stuck_import
        orphan = orphan_queued(queued_at: Time.current)

        travel_to(stall.from_now + 1.minute) do
          expect { sweep }.not_to have_enqueued_job(CampaignImports::ImportJob)
        end
        expect(stalled.reload).to be_importing
        expect(orphan.reload).to be_queued
      end
    end
  end

  it 'is registered in the schedule on the scheduled jobs queue' do
    entry = YAML.load_file(Rails.root.join('config/schedule.yml')).fetch('campaign_imports_stalled_imports_job')

    expect(entry).to include('class' => described_class.name, 'queue' => 'scheduled_jobs')
    expect(described_class.new.queue_name).to eq('scheduled_jobs')
  end
end
