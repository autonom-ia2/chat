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
    expect(result['whatsapp']).to eq('total' => 4, 'receive' => 3, 'opted_out' => 1)
    # SMS (#1004): same mobiles, off until switched on.
    expect(result['sms']).to eq('total' => 4, 'receive' => 0, 'opted_out' => 1)
    expect(result['email']).to eq('total' => 4, 'receive' => 1, 'unsubscribed' => 1, 'bounced' => 1, 'suppressed' => 1)
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
