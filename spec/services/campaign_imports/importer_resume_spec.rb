require 'rails_helper'

# #2921: an import that broke while it was being written goes on from where it stopped when the Importer runs again.
# Rows already imported are skipped, so nothing is written or counted twice.
RSpec.describe CampaignImports::Importer, :aggregate_failures do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }

  before { stub_const('CampaignImports::Importer::BLOCK_SIZE', 2) }

  def run(campaign_import)
    described_class.new(campaign_import).perform
    campaign_import.reload
  end

  # The second of three blocks breaks: two people saved, three to go, the import `failed`.
  def failed_midway(flow)
    campaign_import = queued_import(flow, account: account, user: user)
    break_import_on_block(2, ActiveRecord::StatementInvalid.new('boom'))
    run(campaign_import)
  end

  CampaignImportResumeHelpers::FLOWS.each do |flow|
    context "with the #{flow} flow" do
      it 'keeps the first block when it breaks, then imports every other valid row once' do
        campaign_import = failed_midway(flow)

        expect(campaign_import).to be_failed
        expect(campaign_import).to be_import_resumable
        expect(campaign_import).to have_attributes(imported_contacts_count: 2, failed_contacts_count: 3)
        expect(campaign_import.validation_summary['import_error']).to eq('ActiveRecord::StatementInvalid')
        saved_first = account.contacts.pluck(:id)
        expect(saved_first.size).to eq(2)

        run(campaign_import)

        expect(campaign_import).to be_completed
        expect(campaign_import).to have_attributes(imported_contacts_count: 5, existing_contacts_count: 0, failed_contacts_count: 0)
        expect(campaign_import.validation_summary).not_to have_key('import_error')
        expect(campaign_import.import_finished_at).to be_present
        expect(account.contacts.pluck(:phone_number)).to match_array(resume_phones)
        expect(account.contacts.pluck(:id)).to include(*saved_first)
        expect(campaign_import.campaign_import_rows.status_imported.pluck(:contact_id)).to match_array(account.contacts.pluck(:id))
      end
    end
  end

  it 'drops what the failure left behind as soon as it starts writing again' do
    campaign_import = failed_midway(:contacts)
    expect(campaign_import.import_finished_at).to be_present
    first_start = campaign_import.import_started_at

    travel_to(10.minutes.from_now) do
      kill_import_on_block(campaign_import, 1)

      expect(campaign_import).to be_importing
      expect(campaign_import.import_finished_at).to be_nil
      expect(campaign_import.import_started_at).to be_within(1.second).of(Time.current)
      expect(campaign_import.import_started_at).to be > first_start
      expect(campaign_import.validation_summary).not_to have_key('import_error')
      expect(campaign_import.validation_summary).to have_key('contact_attributes')
    end
  end

  it 'does nothing when another run is already writing the import it was asked to go on with' do
    campaign_import = failed_midway(:audience)
    kill_import_on_block(campaign_import, 1)

    run(campaign_import)

    expect(campaign_import).to be_importing
    expect(account.contacts.count).to eq(2)
  end

  # The sweep (CampaignImports::StalledImportsJob) reads the import's `updated_at` as a sign of life.
  it 'touches the import after each block commits, so a worker that is still writing is not taken for a dead one' do
    campaign_import = queued_import(:audience, account: account, user: user)
    started = Time.current.change(usec: 0)

    travel_to(started) do
      # Ten minutes go by between the start and the first block (reading the file).
      allow_any_instance_of(CampaignImports::NormalizedRows).to receive(:perform).and_wrap_original do |original| # rubocop:disable RSpec/AnyInstance
        travel 10.minutes
        original.call
      end
      kill_import_on_block(campaign_import, 2)

      expect(campaign_import.import_started_at).to be_within(1.second).of(started)
      expect(campaign_import.updated_at).to be_within(1.second).of(started + 10.minutes)
    end
  end

  # Without the lock, two runs of the same import at once would both write the rows of a block.
  it 'locks the rows of each block while it writes them' do
    campaign_import = queued_import(:audience, account: account, user: user)
    queries = []
    recorder = ->(*event) { queries << event.last[:sql] }

    ActiveSupport::Notifications.subscribed(recorder, 'sql.active_record') { run(campaign_import) }

    row_locks = queries.select { |sql| sql.include?('FROM "campaign_import_rows"') && sql.include?('FOR UPDATE') }
    expect(campaign_import).to be_completed
    expect(row_locks.size).to eq(3)
  end

  it 'keeps the number of contact attributes the first pass created (Importar contatos)' do
    campaign_import = failed_midway(:contacts)
    expect(campaign_import.validation_summary['contact_attributes_created']).to eq(1)

    run(campaign_import)

    expect(campaign_import.validation_summary['contact_attributes_created']).to eq(1)
    expect(account.custom_attribute_definitions.where(attribute_key: 'plano').count).to eq(1)
    expect(account.contacts.pluck(:custom_attributes)).to all(eq('plano' => 'Ouro'))
  end

  it 'counts the company once after the second pass (Públicos)' do
    account.enable_features!('companies')
    campaign_import = failed_midway(:audience)

    run(campaign_import)

    expect(campaign_import).to be_completed
    expect(account.companies.count).to eq(1)
    expect(campaign_import).to have_attributes(companies_created_count: 1, companies_reused_count: 0, company_contacts_linked_count: 5)
  end

  it 'labels every contact once and counts them on the base label (campaign base)' do
    campaign_import = failed_midway(:campaign_base)

    run(campaign_import)

    expect(campaign_import.campaign_import_labels.kind_base.sole.applied_count).to eq(5)
    expect(account.contacts.map { |contact| contact.label_list.count(campaign_import.base_label) }).to eq([1] * 5)
  end

  describe 'a row that failed alone in the first pass' do
    # The contact lookup of the first person breaks while `broken` is on.
    def break_first_person
      state = { broken: true }
      allow_any_instance_of(CampaignImports::ContactMatcher).to receive(:find).and_wrap_original do |method, phone| # rubocop:disable RSpec/AnyInstance
        raise ActiveRecord::RecordInvalid, Contact.new if state[:broken] && phone == resume_phones.first

        method.call(phone)
      end
      state
    end

    def failed_with_a_bad_row
      state = break_first_person
      campaign_import = failed_midway(:campaign_base)
      expect(campaign_import).to have_attributes(status: 'failed', imported_contacts_count: 1)
      [campaign_import, state]
    end

    it 'is tried again and, failing again, keeps one error and counts once' do
      campaign_import, = failed_with_a_bad_row

      run(campaign_import)

      expect(campaign_import).to be_completed_with_failures
      expect(campaign_import).to have_attributes(imported_contacts_count: 4, failed_contacts_count: 1)
      expect(campaign_import.campaign_import_rows.status_import_failed.sole.error_messages).to eq(['import_failed:ActiveRecord::RecordInvalid'])
      expect(account.contacts.count).to eq(4)
    end

    it 'is imported when it works the second time, without the old error' do
      campaign_import, state = failed_with_a_bad_row
      state[:broken] = false

      run(campaign_import)

      expect(campaign_import).to be_completed
      expect(campaign_import).to have_attributes(imported_contacts_count: 5, failed_contacts_count: 0)
      expect(campaign_import.campaign_import_rows.pluck(:error_messages)).to all(eq([]))
      expect(account.contacts.pluck(:phone_number)).to match_array(resume_phones)
    end
  end

  describe 'a failed import that is not a writing that broke' do
    def expect_nothing_written(campaign_import)
      expect(campaign_import).not_to be_import_resumable

      run(campaign_import)

      expect(campaign_import).to be_failed
      expect(campaign_import).not_to be_import_resumable
      expect(account.contacts.count).to eq(0)
      expect(campaign_import.campaign_import_rows.status_imported.count).to eq(0)
    end

    it 'is left failed when it never started writing' do
      campaign_import = queued_import(:contacts, account: account, user: user)
      campaign_import.update!(status: :failed)

      expect_nothing_written(campaign_import)
      expect(campaign_import.import_started_at).to be_nil
    end

    it 'is left failed when it is the "Parou" of an automation step, which has no file to read again' do
      campaign_import = automation_import(account: account, user: user, status: :failed)

      expect_nothing_written(campaign_import)
      expect(campaign_import.validation_summary['parou']).to eq('sem_acesso')
    end
  end
end
