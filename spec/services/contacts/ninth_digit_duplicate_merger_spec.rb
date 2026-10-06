require 'rails_helper'

# #990: contacts duplicated by the Brazilian ninth digit are merged into the one that has it.
RSpec.describe Contacts::NinthDigitDuplicateMerger, :aggregate_failures do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  let(:inbox) { create(:inbox, account: account) }
  let!(:base) { create(:contact, account: account, name: 'Ana Souza', phone_number: '+5511987654321', email: 'ana@example.org') }
  let!(:mergee) { create(:contact, account: account, name: 'ana  SOUZA', phone_number: '+551187654321') }

  def run(apply: false, &)
    described_class.new(account: account, apply: apply).perform(&)
  end

  def outcomes(apply: true)
    run(apply: apply).map(&:outcome)
  end

  def import_row(contact)
    campaign_import = create_campaign_import(account: account, user: user, content: "nome,telefone\nAna,11987654321\n")
    CampaignImportRow.create!(campaign_import: campaign_import, row_number: 1, contact: contact)
  end

  def whatsapp_campaign
    channel = create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false)
    create(:campaign, account: account, inbox: channel.inbox, campaign_type: :one_off, scheduled_at: 1.hour.ago)
  end

  def campaign_recipient(campaign, contact)
    CampaignRecipient.create!(account: account, campaign: campaign, inbox: campaign.inbox, contact: contact, status: :sent)
  end

  it 'finds the pair and writes nothing in dry-run' do
    conversation = create(:conversation, account: account, inbox: inbox, contact: mergee)

    results = run

    expect(results.size).to eq(1)
    expect(results.first).to have_attributes(
      base_id: base.id, mergee_id: mergee.id, conversations: 1, name_differs: false, outcome: 'would merge'
    )
    expect(Contact.exists?(mergee.id)).to be(true)
    expect(conversation.reload.contact_id).to eq(mergee.id)
  end

  it 'merges into the contact with the ninth digit, moving conversations, fork rows and labels, and is idempotent' do
    conversation = create(:conversation, account: account, inbox: inbox, contact: mergee)
    row = import_row(mergee)
    email_recipient = create(:email_campaign_recipient, email_campaign: create(:email_campaign, account: account), contact: mergee)
    recipient = campaign_recipient(whatsapp_campaign, mergee)
    mergee.update!(label_list: ['base-import'])

    results = run(apply: true)

    expect(results.map(&:outcome)).to eq(['merged'])
    expect(results.first.repoint).to include('campaign_import_rows' => 1, 'email_campaign_recipients' => 1, 'campaign_recipients' => 1)
    expect(Contact.exists?(mergee.id)).to be(false)
    expect(base.reload.phone_number).to eq('+5511987654321')
    expect(base.label_list).to include('base-import')
    expect([conversation, row, email_recipient, recipient].map { |record| record.reload.contact_id }.uniq).to eq([base.id])
    expect(run(apply: true)).to be_empty
  end

  it 'moves the messages in bulk, without a MESSAGE_UPDATED event per message' do
    conversation = create(:conversation, account: account, inbox: inbox, contact: mergee)
    message = create(:message, account: account, inbox: inbox, conversation: conversation, sender: mergee, message_type: :incoming)
    allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original

    run(apply: true)

    expect(message.reload.sender_id).to eq(base.id)
    expect(Rails.configuration.dispatcher).not_to have_received(:dispatch).with(Events::Types::MESSAGE_UPDATED, any_args)
  end

  it 'unions labels without case differences' do
    base.update!(label_list: ['vip'])
    mergee.update!(label_list: %w[VIP lead])

    run(apply: true)

    expect(base.reload.label_list.map(&:downcase).sort).to eq(%w[lead vip])
  end

  it 'gives the base the company of the merged contact when it has none, keeping the counter' do
    company = create(:company, account: account)
    mergee.update!(company: company)

    run(apply: true)

    expect(base.reload.company_id).to eq(company.id)
    expect(company.reload.contacts_count).to eq(1)
  end

  it 'skips a pair with two different e-mails' do
    mergee.update!(email: 'outra@example.org')

    expect(outcomes).to eq(['skip: email_conflict'])
    expect(Contact.exists?(mergee.id)).to be(true)
  end

  it 'skips a pair with two different identifiers' do
    base.update!(identifier: 'crm-1')
    mergee.update!(identifier: 'crm-2')

    expect(outcomes).to eq(['skip: identifier_conflict'])
  end

  it 'skips a pair from two different companies' do
    base.update!(company: create(:company, account: account))
    mergee.update!(company: create(:company, account: account))

    expect(outcomes).to eq(['skip: company_conflict'])
  end

  it 'skips a pair where only one contact is blocked' do
    mergee.update!(blocked: true)

    expect(outcomes).to eq(['skip: blocked_mismatch'])
  end

  it 'skips a pair with two different names (other person or recycled number) and flags it' do
    mergee.update!(name: 'Bruno Lima')

    results = run

    expect(results.map(&:outcome)).to eq(['skip: name_conflict'])
    expect(results.first.name_differs).to be(true)
  end

  it 'treats accents, case, extra spaces and a phone-as-name as the same or empty name' do
    base.update!(name: 'José  da Silva')
    mergee.update!(name: 'jose da silva')
    expect(outcomes(apply: false)).to eq(['would merge'])

    mergee.update!(name: '+55 11 8765-4321')
    expect(outcomes(apply: false)).to eq(['would merge'])
  end

  it 'skips a pair where both contacts are recipients of the same WhatsApp campaign' do
    campaign = whatsapp_campaign
    campaign_recipient(campaign, base)
    campaign_recipient(campaign, mergee)

    expect(outcomes).to eq(['skip: shared_campaign'])
    expect(Contact.exists?(mergee.id)).to be(true)
  end

  it 'skips a group with more than two contacts' do
    # Legacy data written before the phone uniqueness validation existed.
    third = create(:contact, account: account, phone_number: '+5511900000000')
    third.update_column(:phone_number, '+5511987654321') # rubocop:disable Rails/SkipsModelValidations

    expect(outcomes).to eq(['skip: ambiguous_group'])
    expect(Contact.exists?(mergee.id)).to be(true)
  end

  it 'reports a contact that disappeared mid-run as missing and keeps going' do
    allow(Contacts::NinthDigitMergeAction).to receive(:new).and_raise(ActiveRecord::RecordNotFound)

    expect(outcomes).to eq(['skip: missing'])
  end

  it 'rolls back a pair that fails and reports only the error class' do
    row = import_row(mergee)
    allow(Contacts::NinthDigitMergeAction).to receive(:new).and_raise(RuntimeError, 'Ana Souza +5511987654321')

    expect(outcomes).to eq(['failed: RuntimeError'])
    expect(row.reload.contact_id).to eq(mergee.id)
  end

  it 'yields each result as soon as the pair is processed' do
    create(:contact, account: account, phone_number: '+5521987654321')
    create(:contact, account: account, phone_number: '+552187654321')
    yielded = []

    returned = run { |result| yielded << result }

    expect(yielded.size).to eq(2)
    expect(yielded).to eq(returned)
  end

  it 'ignores landlines, other accounts and numbers that are not duplicated' do
    create(:contact, account: account, phone_number: '+551132654321')
    create(:contact, account: account, phone_number: '+551112345678')
    create(:contact, account: create(:account), phone_number: '+5521987654321')
    create(:contact, account: account, phone_number: '+552187654321')

    expect(run.map(&:mergee_id)).to eq([mergee.id])
  end

  describe 'rake contacts:merge_ninth_digit_duplicates' do
    let(:task) { Rake::Task['contacts:merge_ninth_digit_duplicates'] }
    let(:log) { StringIO.new }
    let(:pii) { ['Ana', 'ana', 'SOUZA', '987654321', '87654321', 'example.org'] }

    around do |example|
      rails_logger = Rails.logger
      record_logger = ActiveRecord::Base.logger
      log_arguments = ActiveJob::Base.log_arguments
      example.run
    ensure
      Rails.logger = rails_logger
      ActiveRecord::Base.logger = record_logger
      ActiveJob::Base.log_arguments = log_arguments
    end

    def invoke(env)
      debug_logger = ActiveSupport::Logger.new(log, level: :debug)
      Rails.logger = debug_logger
      ActiveRecord::Base.logger = debug_logger
      task.reenable
      capture_stdout { with_modified_env(env) { task.invoke } }
    end

    it 'is dry-run by default and prints ids, counts and totals only' do
      output = invoke(ACCOUNT_ID: account.id.to_s)

      expect(output).to include('DRY-RUN', "base=#{base.id} mergee=#{mergee.id}", 'name_differs=false', 'would merge',
                                'totals: pairs=1 would merge=1')
      pii.each { |value| expect(output).not_to include(value) }
      expect(Contact.exists?(mergee.id)).to be(true)
    end

    it 'merges with APPLY=1 without contact data in the logs' do
      expect(invoke(ACCOUNT_ID: account.id.to_s, APPLY: '1')).to include('APPLY', 'merged', 'totals: pairs=1 merged=1')
      expect(Contact.exists?(mergee.id)).to be(false)
      pii.each { |value| expect(log.string).not_to include(value) }
      expect(ActiveJob::Base.log_arguments).to be(false)
    end
  end

  def capture_stdout(&)
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end
end
