require 'rails_helper'

RSpec.describe 'Contracted agent tenant API', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:superadmin) { create(:super_admin) }
  let(:administrator) { create(:user, :administrator, account: account) }
  let(:principal) do
    Autonomia::Agents::Agent.create!(account: create(:account), name: 'Example principal', agent_type: 'custom',
                                     instruction: 'Private principal procedure', scaffold: 'Private principal safety')
  end
  let(:instance) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Example instance', principal_agent: principal, agent_type: 'custom',
                                     store_service_catalog_item_id: SecureRandom.uuid, company_name: 'Example company',
                                     supplemental_instruction: 'Example local detail')
  end
  let(:path) { "/api/v1/accounts/#{account.id}/autonomia/agents/#{instance.id}" }

  before { create(:account_user, account: account, user: superadmin, role: :administrator) }
  around { |example| with_modified_env('AUTONOMIA_AGENTS_ENABLED' => 'true') { example.run } }

  it 'returns inherited metadata without exposing principal instructions or tool credentials' do
    principal.tools.create!(account: principal.account, name: 'Example tool', slug: 'example_tool', endpoint_url: 'https://example.test/tool',
                            headers_config: [{ key: 'x-api-key', value: 'fake-private-header', secret: true }])
    get path, headers: auth_headers(superadmin)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['inherited']['tool_names']).to eq(['Example tool'])
    expect(response.parsed_body['supplemental_instruction']).to eq('Example local detail')
    expect(response.body).not_to include('Private principal procedure', 'Private principal safety', 'fake-private-header', 'headers_config')
  end

  it 'allows local identity/complements but refuses editing the inherited instruction or mode' do
    patch path, params: { agent: { company_name: 'New company', supplemental_instruction: 'New local detail' } },
                headers: auth_headers(superadmin), as: :json
    expect(response).to have_http_status(:ok)
    expect(instance.reload).to have_attributes(company_name: 'New company', supplemental_instruction: 'New local detail')
    patch path, params: { agent: { instruction: 'Override', mode: 'manual' } }, headers: auth_headers(superadmin), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(instance.reload.instruction).to be_nil
    expect(principal.reload.instruction).to eq('Private principal procedure')
  end

  it 'hides contracted instances from ordinary administrators during the SuperAdmin pilot' do
    get path, headers: auth_headers(administrator)
    expect(response).to have_http_status(:not_found)
    instance
    get "/api/v1/accounts/#{account.id}/autonomia/agents", headers: auth_headers(administrator)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.to_json).not_to include('Example instance')
  end

  it 'cannot access a different tenant instance even as SuperAdmin through an account-scoped API' do
    other = create(:account, internal_attributes: { 'autonomia_agents_enabled' => true })
    create(:account_user, account: other, user: superadmin, role: :administrator)
    get "/api/v1/accounts/#{other.id}/autonomia/agents/#{instance.id}", headers: auth_headers(superadmin)
    expect(response).to have_http_status(:not_found)
  end

  it 'filters local complements and inherited tool header configuration from request diagnostics' do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    result = filter.filter('agent' => { 'supplemental_instruction' => 'fake-private-complement' },
                           'headers_config' => [{ 'value' => 'fake-private-header' }])
    expect(result.to_json).not_to include('fake-private-complement', 'fake-private-header')
  end
end
