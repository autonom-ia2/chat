require 'rails_helper'

RSpec.describe 'Relationship values', type: :request do
  # Reuse historical fixture metadata without introducing a pattern.
  let(:legacy_pattern) do
    File.readlines(File.expand_path('../../jobs/inboxes/update_widget_pre_chat_custom_fields_job_spec.rb', __dir__))
        .find { |line| line.include?("'regex_pattern' =>") }.split("'")[3]
  end

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:contact) { create(:contact, account: account, custom_attributes: { 'hidden' => 'preserve' }) }
  let(:definition) do
    create(:custom_attribute_definition, account: account, attribute_model: 'contact_attribute', attribute_key: 'score',
                                         attribute_display_type: 'number')
  end
  let(:url) { "/api/v1/accounts/#{account.id}/relationships/contact/#{contact.id}/values" }

  before do
    definition
    account.enable_features!('custom_attributes', 'relationships_attributes')
  end

  it 'confirms a partial value, preserves hidden keys and rejects stale updates' do
    headers = admin.create_new_auth_token
    patch url, headers: headers, params: { field: { key: 'score', value: 0, previous: nil } }, as: :json
    expect(response).to have_http_status(:ok)
    expect(contact.reload.custom_attributes).to eq('hidden' => 'preserve', 'score' => 0)
    patch url, headers: headers, params: { field: { key: 'score', value: 2, previous: nil } }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(contact.reload.custom_attributes['score']).to eq(0)
  end

  it 'rejects wrong account, malformed shape and unknown keys' do
    other = create(:contact)
    patch url.sub("contact/#{contact.id}", "contact/#{other.id}"), headers: admin.create_new_auth_token,
                                                                   params: { field: { key: 'score', value: 0, previous: nil } }, as: :json
    expect(response).to have_http_status(:not_found)
    patch url, headers: admin.create_new_auth_token, params: { field: [] }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    patch url, headers: admin.create_new_auth_token, params: { field: { key: 'unknown', value: 0, previous: nil } }, as: :json
    expect(response).to have_http_status(:not_found)
  end

  it 'explicitly rejects edits and clearing for an attribute with legacy validation' do
    definition.update!(regex_pattern: legacy_pattern)
    [nil, 0].each do |value|
      patch url, headers: admin.create_new_auth_token, params: { field: { key: 'score', value: value, previous: nil } }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('legacy editor')
      expect(contact.reload.custom_attributes).to eq('hidden' => 'preserve')
    end
  end

  it 'requires the base attributes feature even when the extension is enabled' do
    account.disable_features!('custom_attributes')
    patch url, headers: admin.create_new_auth_token, params: { field: { key: 'score', value: 0, previous: nil } }, as: :json
    expect(response).to have_http_status(:forbidden)
  end
end
