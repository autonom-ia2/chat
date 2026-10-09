require 'rails_helper'

RSpec.describe 'Enterprise Autonomia agent audit logs', type: :request do
  let!(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:super_admin) { create(:super_admin, name: 'Operador global', email: 'operator@example.com') }
  let!(:agent) do
    Autonomia::Agents::Agent.create!(
      account: account,
      name: 'Agente auditado',
      agent_type: 'custom',
      instruction: 'Instrução que nunca deve ir para a trilha.',
      config: { 'test_allowlist_phones' => ['+5511999999999'] }
    )
  end
  let!(:other_agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Outro agente', agent_type: 'custom', config: {})
  end
  let!(:matching_audit) do
    Enterprise::AuditLog.create!(
      auditable: agent,
      associated: account,
      user: super_admin,
      user_type: 'SuperAdmin',
      action: 'update',
      audited_changes: {
        'operation_config' => {
          'test_allowlist_phones' => {
            'old' => ['+55••••••99'],
            'new' => ['+55••••••88']
          }
        }
      },
      created_at: 1.minute.ago
    )
  end
  let(:other_key_audit) do
    Enterprise::AuditLog.create!(
      auditable: agent,
      associated: account,
      user: super_admin,
      user_type: 'SuperAdmin',
      action: 'update',
      audited_changes: { 'operation_config' => { 'voice_reply' => { 'old' => false, 'new' => true } } },
      created_at: 2.minutes.ago
    )
  end
  let(:other_agent_audit) do
    Enterprise::AuditLog.create!(
      auditable: other_agent,
      associated: account,
      user: super_admin,
      user_type: 'SuperAdmin',
      action: 'update',
      audited_changes: { 'operation_config' => { 'test_allowlist_phones' => { 'old' => [], 'new' => [] } } },
      created_at: 3.minutes.ago
    )
  end

  before do
    account.enable_features(:audit_logs)
    account.save!
    other_key_audit
    other_agent_audit
  end

  # This assertion set is intentionally broad: it proves actor normalization,
  # masking and the exact filter result in one response.
  # rubocop:disable RSpec/MultipleExpectations
  it 'filters by agent and operation key and exposes a normalized SuperAdmin actor' do
    query = Rack::Utils.build_nested_query(
      types: ['Autonomia::Agents::Agent'],
      agent_id: agent.id,
      operation_key: 'test_allowlist_phones'
    )
    get "/api/v1/accounts/#{account.id}/audit_logs?#{query}",
        headers: admin.create_new_auth_token.merge('ACCEPT' => 'application/json')

    expect(response).to have_http_status(:success)
    payload = response.parsed_body
    expect(payload['audit_logs'].pluck('id')).to eq([matching_audit.id])

    entry = payload['audit_logs'].sole
    expect(entry).to include(
      'auditable_id' => agent.id,
      'auditable_type' => 'Autonomia::Agents::Agent',
      'user_id' => super_admin.id,
      'user_type' => 'SuperAdmin',
      'username' => super_admin.email,
      'action' => 'update'
    )
    expect(entry['actor']).to include(
      'type' => 'SuperAdmin', 'id' => super_admin.id, 'name' => super_admin.name
    )
    expect(entry['operation_key']).to eq('test_allowlist_phones')
    expect(entry['audited_changes']).to eq(matching_audit.audited_changes)
    expect(entry['audited_changes'].to_json).not_to include('+5511999999999', agent.instruction)
    expect(entry['created_at']).to be_positive
  end
  # rubocop:enable RSpec/MultipleExpectations

  it 'does not return agent audits through another account' do
    other_account = create(:account)
    foreign_agent = Autonomia::Agents::Agent.create!(account: other_account, name: 'Fora', agent_type: 'custom', config: {})
    foreign_audit = Enterprise::AuditLog.create!(
      auditable: foreign_agent,
      associated: other_account,
      user: super_admin,
      user_type: 'SuperAdmin',
      action: 'update',
      audited_changes: { 'operation_config' => { 'voice_reply' => { 'old' => false, 'new' => true } } }
    )

    query = Rack::Utils.build_nested_query(
      types: ['Autonomia::Agents::Agent'],
      agent_id: foreign_agent.id
    )
    get "/api/v1/accounts/#{account.id}/audit_logs?#{query}",
        headers: admin.create_new_auth_token.merge('ACCEPT' => 'application/json')

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['audit_logs'].pluck('id')).not_to include(foreign_audit.id)
  end

  it 'returns no rows for an invalid operation filter' do
    query = Rack::Utils.build_nested_query(
      types: ['Autonomia::Agents::Agent'],
      agent_id: agent.id,
      operation_key: 'operation_that_does_not_exist'
    )
    get "/api/v1/accounts/#{account.id}/audit_logs?#{query}",
        headers: admin.create_new_auth_token.merge('ACCEPT' => 'application/json')

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['audit_logs']).to eq([])
  end
end
