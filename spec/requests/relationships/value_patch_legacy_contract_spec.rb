require 'rails_helper'

RSpec.describe Relationships::ValuePatch, type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  before { account.enable_features!('custom_attributes', 'companies', 'relationships_attributes') }

  %w[contact company].each do |entity|
    it "accepts a full unversioned #{entity} payload as an intentional last write" do
      record = create(entity.to_sym, account: account, custom_attributes: { 'first' => 'old', 'second' => 'old' })
      create(:custom_attribute_definition, account: account, attribute_model: "#{entity}_attribute", attribute_key: 'first',
                                           attribute_display_type: 'text')
      snapshot = record.custom_attributes.deep_dup
      described_class.new(record, "#{entity}_attribute").update!('key' => 'first', 'value' => 'confirmed', 'previous' => 'old')
      snapshot['second'] = 'intentional'
      payload = { custom_attributes: snapshot }
      payload = { company: payload } if entity == 'company'

      patch "/api/v1/accounts/#{account.id}/#{entity.pluralize}/#{record.id}", headers: admin.create_new_auth_token, params: payload, as: :json

      expect(response).to have_http_status(:ok)
      expect(record.reload.custom_attributes).to eq('first' => 'old', 'second' => 'intentional')
      expect do
        described_class.new(record, "#{entity}_attribute").update!('key' => 'first', 'value' => 'next', 'previous' => 'confirmed')
      end.to(raise_error { |error| expect(error.class.name).to eq('Relationships::Configuration::Conflict') })
    end
  end
end
