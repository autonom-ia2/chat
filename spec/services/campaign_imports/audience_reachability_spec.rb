require 'rails_helper'

# #993 (PRD B8): who in an audience does not receive, per channel, before any send.
RSpec.describe CampaignImports::AudienceReachability, :aggregate_failures do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  let(:content) do
    "Nome,Celular,Email\n" \
      "Ana,11987654321,ana@alfa.com.br\n" \
      "Bia,21987654321,bia@beta.com.br\n" \
      "Caio,31987654321,caio@gama.com.br\n" \
      "Duda,41987654321,duda@delta.com.br\n"
  end

  def validated_audience
    campaign_import = create_audience_import(account: account, user: user, content: content)
    campaign_import.update!(schema_resolution: { 'manual_mapping' => { 'name' => 0, 'phone' => 1, 'email' => 2 },
                                                 'header_row' => 1, 'table_index' => 0 })
    CampaignImports::AudienceValidator.new(campaign_import).perform
    campaign_import.reload
  end

  it 'counts refusals, unsubscribes, bounces and other suppressions before saving' do
    # Stored without the 9th digit: still the same person (B7/D6).
    account.contacts.create!(name: 'Ana antiga', phone_number: '+551187654321').opt_out!(source: 'manual')
    EmailSuppression.create!(account: account, email: 'BIA@beta.com.br', reason: 'unsubscribe', source: 'manual')
    EmailSuppression.create!(account: account, email: 'caio@gama.com.br', reason: 'hard_bounce', source: 'ses')
    EmailSuppressionState.create!(account: account, email: 'duda@delta.com.br', reason: 'complaint', active: true)
    campaign_import = validated_audience

    result = described_class.new(campaign_import).perform

    expect(campaign_import).to be_ready_to_confirm
    expect(result['whatsapp']).to eq('total' => 4, 'receive' => 3, 'opted_out' => 1, 'blocked' => 0)
    # SMS (#1004): same mobiles, off until switched on.
    expect(result['sms']).to eq('total' => 4, 'receive' => 0, 'opted_out' => 1, 'blocked' => 0)
    expect(result['email']).to eq('total' => 4, 'receive' => 1, 'opted_out' => 0, 'blocked' => 0,
                                  'unsubscribed' => 1, 'bounced' => 1, 'suppressed' => 1)
  end

  # chat#2733: a blocked contact does not receive either; refused and blocked at once counts as refused.
  it 'counts blocked contacts apart, without counting a person twice' do
    account.contacts.create!(name: 'Bia', phone_number: '+5521987654321', blocked: true)
    account.contacts.create!(name: 'Caio', phone_number: '+5531987654321', blocked: true).opt_out!(source: 'manual')
    campaign_import = validated_audience
    campaign_import.update!(channels: campaign_import.channels.merge('sms' => { 'enabled' => true, 'count' => 4 }))

    result = described_class.new(campaign_import).perform

    expect(result['whatsapp']).to eq('total' => 4, 'receive' => 2, 'opted_out' => 1, 'blocked' => 1)
    expect(result['sms']).to eq('total' => 4, 'receive' => 2, 'opted_out' => 1, 'blocked' => 1)
  end

  # chat#2733: e-mail follows the send — the contact of the account with that address refused or is blocked → does not
  # receive; refused before blocked, and someone refused or blocked is not counted again in a suppression bucket.
  it 'leaves out e-mails of contacts that refused or are blocked, each person once' do
    account.contacts.create!(name: 'Ana', email: 'ANA@alfa.com.br').opt_out!(source: 'manual')
    account.contacts.create!(name: 'Bia', email: 'bia@beta.com.br', blocked: true)
    account.contacts.create!(name: 'Caio', email: 'caio@gama.com.br', blocked: true).opt_out!(source: 'manual')
    account.contacts.create!(name: 'Duda', email: 'duda@delta.com.br', blocked: true)
    EmailSuppression.create!(account: account, email: 'duda@delta.com.br', reason: 'unsubscribe', source: 'manual')

    result = described_class.new(validated_audience).perform

    expect(result['email']).to eq('total' => 4, 'receive' => 0, 'opted_out' => 2, 'blocked' => 2,
                                  'unsubscribed' => 0, 'bounced' => 0, 'suppressed' => 0)
  end

  it 'ignores refusals and blocks of contacts of other accounts on e-mail' do
    create(:account).contacts.create!(name: 'Ana', email: 'ana@alfa.com.br', blocked: true)

    result = described_class.new(validated_audience).perform

    expect(result['email']).to include('receive' => 4, 'opted_out' => 0, 'blocked' => 0)
  end

  it 'gives nobody on a channel that is switched off' do
    campaign_import = validated_audience
    campaign_import.update!(channels: campaign_import.channels.merge('email' => { 'enabled' => false, 'count' => 4 }))

    result = described_class.new(campaign_import).perform

    expect(result['email']).to include('total' => 4, 'receive' => 0)
    expect(result['whatsapp']).to include('receive' => 4, 'opted_out' => 0)
  end

  it 'ignores contacts and suppressions of other accounts' do
    other_account = create(:account)
    other_account.contacts.create!(name: 'Ana', phone_number: '+5511987654321').opt_out!(source: 'manual')
    EmailSuppression.create!(account: other_account, email: 'ana@alfa.com.br', reason: 'unsubscribe', source: 'manual')

    result = described_class.new(validated_audience).perform

    expect(result['whatsapp']['opted_out']).to eq(0)
    expect(result['email']['unsubscribed']).to eq(0)
  end
end
