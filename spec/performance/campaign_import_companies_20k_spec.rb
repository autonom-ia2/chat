require 'rails_helper'

# #998 on top of PRD #990 acceptance B10: an audience of 20.000 rows with a company column
# (200 distinct companies) still validates and imports in under 5 minutes, and the numbers
# shown before saving equal the final ones. Slow on purpose, so it runs only on demand:
#   RUN_PERF=1 bundle exec rspec spec/performance/campaign_import_companies_20k_spec.rb
# Runs outside the fixture transaction so each block commits as it does in production.
RSpec.describe 'Audience import with 20.000 rows and companies', type: :model do
  self.use_transactional_tests = false

  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:rows) { 20_000 }
  let(:companies) { 200 }

  before { skip 'set RUN_PERF=1 to run' unless ENV['RUN_PERF'] == '1' }

  after do
    next unless ENV['RUN_PERF'] == '1'

    contacts = Contact.where(account_id: account.id)
    ActsAsTaggableOn::Tagging.where(taggable_type: 'Contact', taggable_id: contacts.select(:id)).delete_all
    contacts.delete_all
    Company.where(account_id: account.id).delete_all
  end

  it 'finishes within 5 minutes and reports the previewed company numbers' do
    account.enable_features!('companies')
    create(:company, :without_domain, account: account, name: 'Corretora 1')
    lines = (1..rows).map { |i| "Pessoa #{i},+55119#{format('%08d', i)},corretora  #{(i % companies) + 1}" }
    campaign_import = create_audience_import(account: account, user: account_and_user.last, content: "nome,telefone,corretora\n#{lines.join("\n")}\n")
    campaign_import.update!(schema_resolution: { 'manual_mapping' => { 'name' => 0, 'phone' => 1, 'company' => 2 }, 'header_row' => 1,
                                                 'table_index' => 0 })
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    CampaignImports::AudienceValidator.new(campaign_import).perform
    validated = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    campaign_import.reload.update!(status: :queued)
    CampaignImports::Importer.new(campaign_import).perform

    finished = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    timings = { validation: validated - started, import: finished - validated, total: finished - started }.transform_values { |value| value.round(1) }
    puts "\n[perf #998] #{timings}"
    campaign_import.reload
    preview = campaign_import.validation_summary['companies']
    expect(finished - started).to be < 300
    expect(campaign_import).to be_completed
    expect(preview).to include('companies_created' => companies - 1, 'companies_reused' => 1, 'contacts_linked' => rows, 'contacts_kept' => 0)
    expect([campaign_import.companies_created_count, campaign_import.companies_reused_count,
            campaign_import.company_contacts_linked_count, campaign_import.companies_kept_count]).to eq([companies - 1, 1, rows, 0])
    expect(Company.where(account_id: account.id).count).to eq(companies)
    expect(Contact.where(account_id: account.id, company_id: nil).count).to eq(0)
  end
end
