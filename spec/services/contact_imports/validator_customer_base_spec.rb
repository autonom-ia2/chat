require 'rails_helper'

# Base de clientes (#1246): the contact import path with the customer_base flag on and off. With it
# off the reading is the classic one; with it on, legacy mobiles get the ninth digit only when Jev says
# the phone column is Brazilian, cells with several values are read and every part stays masked.
RSpec.describe ContactImports::Validator, :aggregate_failures do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  let(:content) { "Nome,Celular\nAna Souza,(11) 8765-4321\nBia Lima,(11) 3456-7890 / (11) 3456-7891\nCaio Reis,21987654321\n" }

  before { enable_audience_jev }

  def validated(phone_country: nil)
    stub_audience_jev(phone: 'column_1', email: 'none', name: 'column_0', company: 'none', phone_country: phone_country)
    campaign_import = create_contact_import(account: account, user: user, content: content)
    described_class.new(campaign_import).perform
    campaign_import.reload
  end

  def masked_phones(campaign_import)
    campaign_import.campaign_import_rows.order(:row_number).pluck(:raw_phone_masked)
  end

  context 'when customer_base is on' do
    before { account.enable_features!('customer_base') }

    it 'creates the contact with the ninth digit when Jev says the column is Brazilian' do
      campaign_import = validated(phone_country: 'brazil')

      expect(campaign_import.valid_rows).to eq(2)
      expect(campaign_import.validation_summary['ninth_digit_added']).to eq(1)
      import_contacts!(campaign_import)
      expect(account.contacts.pluck(:phone_number)).to contain_exactly('+5511987654321', '+5521987654321')
    end

    it 'keeps the legacy number out when Jev says another country' do
      campaign_import = validated(phone_country: 'other')

      expect(campaign_import.valid_rows).to eq(1)
      expect(campaign_import.validation_summary).to include('phone_country' => 'other', 'legacy_mobiles_refused' => 1)
    end

    it 'masks every number of an invalid cell on its own' do
      masked = masked_phones(validated(phone_country: 'brazil')).second

      expect(masked.split('; ').size).to eq(2)
      expect(masked).not_to include('3456')
    end

    it 'sends Jev counts and masked formats with only the DDD visible, never a number' do
      requests = stub_audience_jev(phone: 'column_1', email: 'none', name: 'column_0', company: 'none', phone_country: 'brazil')
      described_class.new(create_contact_import(account: account, user: user, content: content)).perform

      expect(requests.first.dig('state', 'profiles', 1)).to include('legacy_mobile_count' => 1)
      expect(requests.first.dig('state', 'profiles', 1, 'examples')).to include('(11) 0000-0000')
      expect(requests.to_json).not_to include('8765', '3456', '98765', 'Souza')
    end
  end

  context 'when customer_base is off' do
    it 'reads as before: no country question, no ninth digit, the classic mask' do
      requests = stub_audience_jev(phone: 'column_1', email: 'none', name: 'column_0', company: 'none')
      campaign_import = create_contact_import(account: account, user: user, content: content)
      described_class.new(campaign_import).perform
      campaign_import.reload

      expect(requests.first['questions']).not_to have_key('phone_country')
      expect(campaign_import.valid_rows).to eq(1)
      expect(campaign_import.validation_summary).not_to have_key('ninth_digit_added')
      expect(masked_phones(campaign_import).second).to eq(CampaignImports::PhoneNormalizer.mask_raw('(11) 3456-7890 / (11) 3456-7891'))
    end

    it 'reads a file saved without a header under customer_base as the classic reading would' do
      campaign_import = create_contact_import(account: account, user: user, content: "Ana,11987654321\nBia,21987654321\n")
      manual = { 'name' => 0, 'phone' => 1, 'email' => nil, 'company' => nil }
      campaign_import.update!(schema_resolution: { 'manual_mapping' => manual, 'header_row' => 0, 'table_index' => 0 })

      described_class.new(campaign_import).perform

      expect(campaign_import.reload).to be_validation_failed
      expect(campaign_import.validation_summary['errors']).to have_key('empty_file')
    end
  end
end
