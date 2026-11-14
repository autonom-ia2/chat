require 'rails_helper'

# #2921: "confirmar" again on an import that broke while it was being written puts it back in the queue, and it goes
# on from where it stopped. Importar contatos confirms on /contact_imports; Públicos and the campaign base on
# /campaign_imports.
RSpec.describe 'Import retry through confirm (#2921)', :aggregate_failures, type: :request do
  let!(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:admin) { account_and_user.last }
  let(:auth_headers) { { 'api_access_token' => admin.access_token.token } }

  around do |example|
    with_modified_env('CAMPAIGN_JOURNEY_ENABLED' => 'true', 'CAMPAIGN_IMPORT_ENABLED' => 'true') { example.run }
  end

  before { stub_const('CampaignImports::Importer::BLOCK_SIZE', 2) }

  def confirm_path(campaign_import)
    resource = campaign_import.contact_import? ? 'contact_imports' : 'campaign_imports'
    "/api/v1/accounts/#{account.id}/#{resource}/#{campaign_import.id}/confirm"
  end

  def confirm(campaign_import)
    post confirm_path(campaign_import), headers: auth_headers
  end

  # The second of three blocks breaks: two people saved, three to go, the import `failed`.
  def failed_midway(flow)
    campaign_import = queued_import(flow, account: account, user: admin)
    break_import_on_block(2, ActiveRecord::StatementInvalid.new('boom'))
    CampaignImports::Importer.new(campaign_import).perform
    campaign_import.reload
  end

  def expect_refused(campaign_import)
    expect { confirm(campaign_import) }.not_to have_enqueued_job(CampaignImports::ImportJob)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('campaign_import.not_ready')
    expect(campaign_import.reload).to be_failed
  end

  CampaignImportResumeHelpers::FLOWS.each do |flow|
    context "with the #{flow} flow" do
      it 'ends completed, with every valid row imported once, when the failed import is confirmed again' do
        campaign_import = failed_midway(flow)
        expect(campaign_import).to have_attributes(status: 'failed', imported_contacts_count: 2, failed_contacts_count: 3)

        perform_enqueued_jobs { confirm(campaign_import) }

        expect(response).to have_http_status(:ok)
        campaign_import.reload
        expect(campaign_import).to be_completed
        expect(campaign_import).to have_attributes(imported_contacts_count: 5, existing_contacts_count: 0, failed_contacts_count: 0)
        expect(campaign_import.validation_summary).not_to have_key('import_error')
        expect(account.contacts.pluck(:phone_number)).to match_array(resume_phones)
      end

      it 'enqueues the writing once when the failed import is confirmed twice in a row' do
        campaign_import = failed_midway(flow)

        expect { confirm(campaign_import) }.to have_enqueued_job(CampaignImports::ImportJob).with(campaign_import).exactly(:once)
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['payload']['status']).to eq('queued')

        expect { confirm(campaign_import) }.not_to have_enqueued_job(CampaignImports::ImportJob)
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('campaign_import.not_ready')
        expect(campaign_import.reload).to be_queued
      end
    end
  end

  # #2896: someone asked to undo the list ("Desfazer"). Writing the missing rows while the undo removes the written
  # ones, or after it removed them, would bring back half of what was undone. An undo that failed is asked again.
  describe 'a failed import that someone asked to undo' do
    %i[processing completed failed].each do |undo_status|
      it "refuses to go on while the undo is #{undo_status}, on the route and in the writer" do
        campaign_import = failed_midway(:contacts)
        campaign_import.update!(undo_status: undo_status)

        expect(campaign_import).not_to be_import_resumable
        expect_refused(campaign_import)
        expect(CampaignImports::Importer.new(campaign_import).send(:startable?)).to be(false)
        expect(account.contacts.count).to eq(2)
      end
    end
  end

  describe 'a failed import that is not a writing that broke' do
    it 'refuses a contact import that never started writing' do
      campaign_import = queued_import(:contacts, account: account, user: admin)
      campaign_import.update!(status: :failed)

      expect_refused(campaign_import)
    end

    it 'refuses an audience that never started writing' do
      campaign_import = queued_import(:audience, account: account, user: admin)
      campaign_import.update!(status: :failed)

      expect_refused(campaign_import)
    end

    it 'refuses the "Parou" of an automation step, which has no file to read again' do
      expect_refused(automation_import(account: account, user: admin, status: :failed))
    end

    # The 30-day cleanup (PurgeExpiredFilesJob) took the normalized file: there is nothing to go on from.
    %i[contacts audience].each do |flow|
      it "refuses the #{flow} import that broke while writing once its normalized file is gone" do
        campaign_import = failed_midway(flow)
        campaign_import.normalized_csv.purge
        campaign_import.reload
        expect(campaign_import).not_to be_import_resumable

        expect_refused(campaign_import)
        expect(campaign_import).to have_attributes(imported_contacts_count: 2, failed_contacts_count: 3)
        expect(campaign_import.validation_summary['import_error']).to eq('ActiveRecord::StatementInvalid')
        expect(account.contacts.count).to eq(2)
      end
    end
  end
end
