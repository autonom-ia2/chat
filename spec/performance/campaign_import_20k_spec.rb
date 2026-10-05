require 'rails_helper'

# PRD #990 acceptance B10: 20.000 rows import in under 5 minutes, in blocks, and a
# simulated failure marks only that row. Slow on purpose, so it runs only on demand:
#   RUN_PERF=1 bundle exec rspec spec/performance/campaign_import_20k_spec.rb
# Runs outside the fixture transaction so each block commits as it does in production.
RSpec.describe 'Campaign import with 20.000 rows', type: :model do
  self.use_transactional_tests = false

  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:rows) { 20_000 }
  let(:failing_phone) { '+5511900010000' }

  before { skip 'set RUN_PERF=1 to run' unless ENV['RUN_PERF'] == '1' }

  after do
    next unless ENV['RUN_PERF'] == '1'

    contacts = Contact.where(account_id: account.id)
    ActsAsTaggableOn::Tagging.where(taggable_type: 'Contact', taggable_id: contacts.select(:id)).delete_all
    contacts.delete_all
  end

  it 'finishes within 5 minutes and isolates the failing row' do
    user = account_and_user.last
    lines = (1..rows).map { |i| "Pessoa #{i},+55119#{format('%08d', i)}" }
    campaign_import = create_campaign_import(account: account, user: user, content: "nome,telefone\n#{lines.join("\n")}\n", batch_count: 1)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    CampaignImports::Validator.new(campaign_import).perform
    campaign_import.reload.update!(status: :queued)
    importer = CampaignImports::Importer.new(campaign_import)
    allow(importer).to receive(:find_existing_contact).and_wrap_original do |method, phone|
      raise ActiveRecord::RecordInvalid, Contact.new if phone == failing_phone

      method.call(phone)
    end
    importer.perform

    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    campaign_import.reload
    expect(elapsed).to be < 300
    expect(campaign_import.imported_contacts_count).to eq(rows - 1)
    expect(campaign_import.failed_contacts_count).to eq(1)
    expect(account.contacts.tagged_with(campaign_import.base_label, on: :labels).count).to eq(rows - 1)
  end
end
