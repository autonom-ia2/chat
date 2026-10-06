require 'rails_helper'

# #990: contacts duplicated by the Brazilian ninth digit are merged into the one that has it.
RSpec.describe Contacts::NinthDigitDuplicateMerger, :aggregate_failures do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  let(:inbox) { create(:inbox, account: account) }
  let!(:base) { create(:contact, account: account, name: 'Ana Nove', phone_number: '+5511987654321', email: 'ana@example.org') }
  let!(:mergee) { create(:contact, account: account, name: 'Ana Oito', phone_number: '+551187654321') }

  def run(apply: false)
    described_class.new(account: account, apply: apply).perform
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
    expect(results.first).to have_attributes(base_id: base.id, mergee_id: mergee.id, conversations: 1, outcome: 'would merge')
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

  it 'skips a pair with two different e-mails' do
    mergee.update!(email: 'outra@example.org')

    expect(run(apply: true).map(&:outcome)).to eq(['skip: email_conflict'])
    expect(Contact.exists?(mergee.id)).to be(true)
  end

  it 'skips a pair from two different companies' do
    base.update!(company: create(:company, account: account))
    mergee.update!(company: create(:company, account: account))

    expect(run(apply: true).map(&:outcome)).to eq(['skip: company_conflict'])
  end

  it 'skips a pair where both contacts are recipients of the same WhatsApp campaign' do
    campaign = whatsapp_campaign
    campaign_recipient(campaign, base)
    campaign_recipient(campaign, mergee)

    expect(run(apply: true).map(&:outcome)).to eq(['skip: shared_campaign'])
    expect(Contact.exists?(mergee.id)).to be(true)
  end

  it 'skips a group with more than two contacts' do
    # Legacy data written before the phone uniqueness validation existed.
    third = create(:contact, account: account, phone_number: '+5511900000000')
    third.update_column(:phone_number, '+5511987654321') # rubocop:disable Rails/SkipsModelValidations

    expect(run(apply: true).map(&:outcome)).to eq(['skip: ambiguous_group'])
    expect(Contact.exists?(mergee.id)).to be(true)
  end

  it 'ignores landlines, other accounts and numbers that are not duplicated' do
    create(:contact, account: account, phone_number: '+551132654321')
    create(:contact, account: account, phone_number: '+551112345678')
    create(:contact, account: create(:account), phone_number: '+5521987654321')
    create(:contact, account: account, phone_number: '+552187654321')

    expect(run.map(&:mergee_id)).to eq([mergee.id])
  end

  it 'runs from the rake task, dry-run by default, printing ids and counts only' do
    task = Rake::Task['contacts:merge_ninth_digit_duplicates']
    invoke = lambda do |env|
      task.reenable
      with_modified_env(env) { task.invoke }
    end

    output = capture_stdout { invoke.call(ACCOUNT_ID: account.id.to_s) }

    expect(output).to include('DRY-RUN', "base=#{base.id} mergee=#{mergee.id}", 'would merge')
    ['Ana', '987654321', '87654321', 'example.org'].each { |pii| expect(output).not_to include(pii) }
    expect(Contact.exists?(mergee.id)).to be(true)

    expect(capture_stdout { invoke.call(ACCOUNT_ID: account.id.to_s, APPLY: '1') }).to include('APPLY', 'merged')
    expect(Contact.exists?(mergee.id)).to be(false)
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
