require 'rails_helper'

RSpec.describe Autonomia::Store::AgentInstance do
  let(:account) { create(:account) }
  let(:owner_account) { create(:account) }
  let(:user) { create(:super_admin) }
  let(:principal) do
    Autonomia::Agents::Agent.create!(account: owner_account, name: 'Principal fictitious', instruction: 'Principal procedure.',
                                     scaffold: 'Principal safety.', agent_type: 'custom', enabled: true, status: :active)
  end
  let(:activation) do
    Autonomia::Store::Activation.create!(
      user: user, account: account, buyer_subject: 'example-buyer', installation_id: 'chat-test',
      product_catalog_item_id: '22222222-2222-4222-8222-222222222222', service_catalog_item_id: SecureRandom.uuid,
      service_subscription_id: SecureRandom.uuid, target: { 'type' => 'agent', 'installationId' => 'chat-test', 'principalAgentId' => principal.id },
      resource_id: account.id.to_s, metric_key: 'accounts', operation_intent: SecureRandom.uuid, occurred_at: Time.current,
      reservation_id: SecureRandom.uuid, state: 'ready'
    )
  end
  let(:instance) { described_class.provision!(activation) }
  let(:snapshot) do
    { 'effectiveAccess' => 'granted', 'grants' => [{ 'serviceSubscriptionId' => activation.service_subscription_id,
                                                     'reservationId' => activation.reservation_id, 'status' => 'granted',
                                                     'effectiveUntil' => 1.day.from_now.iso8601 }] }
  end

  around do |example|
    with_modified_env('FINANCIAL_STORE_INSTALLATION_ID' => 'chat-test',
                      'FINANCIAL_STORE_PRODUCT_CATALOG_ITEM_ID' => '22222222-2222-4222-8222-222222222222') { example.run }
  end

  it 'reuses one linked instance without copying prompt, knowledge or tools' do
    first = instance
    expect { described_class.provision!(activation.reload) }.not_to change(Autonomia::Agents::Agent, :count)
    expect(first).to have_attributes(account_id: account.id, principal_agent_id: principal.id, instruction: nil, scaffold: nil)
    expect(first.sources.count).to eq(0)
    expect(first.tools.count).to eq(0)
    expect(activation.reload.agent_id).to eq(first.id)
  end

  it 'shares the technical instance between independent buyer contracts' do
    first = instance
    second = activation.dup
    second.user = create(:super_admin)
    second.service_subscription_id = SecureRandom.uuid
    second.operation_intent = SecureRandom.uuid
    second.save!
    expect(described_class.provision!(second).id).to eq(first.id)
  end

  it 'preserves local complements when the principal changes' do
    instance.update!(name: 'Customer assistant', company_name: 'Customer company', supplemental_instruction: 'Customer detail.')
    principal.update!(instruction: 'New principal procedure.')
    result = instance.reload.instrucao_do_sistema
    expect(result).to include('New principal procedure.', 'Customer detail.', 'Customer assistant', 'Customer company')
    expect(instance.instruction).to be_nil
    expect(instance.effective_scaffold).to eq('Principal safety.')
  end

  it 'does not resurrect a logically deleted instance' do
    instance.update_columns(deleted_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    expect { described_class.provision!(activation.reload) }.to raise_error(Autonomia::Financial::StoreClientError) do |error|
      expect(error.code).to eq('AGENT_INSTANCE_DELETED')
    end
  end

  it 'rejects system principals and a chain of instances' do
    principal.update!(config: { 'system_key' => 'example' })
    expect { described_class.provision!(activation) }.to raise_error(Autonomia::Financial::StoreClientError)
    principal.update!(config: {})
    target = activation.target.merge('principalAgentId' => instance.id)
    expect { described_class.principal!(target) }.to raise_error(Autonomia::Financial::StoreClientError)
  end

  it 'blocks the instance before any confirmed grant without calling AI' do
    expect(Crm::Ai::CredentialResolver).not_to receive(:new)
    expect(instance.operating?).to be(false)
    result = Autonomia::Agents::Answerer.new(agent: instance, query: 'example', trust_instruction: true).answer
    expect(result.reply).to be_nil
    expect(result.error).to eq('store_access_denied')
  end

  it 'keeps access while another buyer grant remains and stops when the last grant expires' do
    instance
    projection = Autonomia::Store::Entitlement.create!(account: account, installation_id: activation.installation_id,
                                                       product_catalog_item_id: activation.product_catalog_item_id,
                                                       service_catalog_item_id: activation.service_catalog_item_id, payload: snapshot)
    expect(instance.operating?).to be(true)
    second = activation.dup
    second.user = create(:super_admin)
    second.service_subscription_id = SecureRandom.uuid
    second.reservation_id = SecureRandom.uuid
    second.save!
    grant = snapshot['grants'].first.merge('serviceSubscriptionId' => second.service_subscription_id, 'reservationId' => second.reservation_id)
    activation.update!(state: 'disabled')
    projection.update!(payload: { 'effectiveAccess' => 'granted', 'grants' => [grant] })
    expect(instance.reload.operating?).to be(true)
    projection.update!(payload: { 'effectiveAccess' => 'granted', 'grants' => [grant.merge('effectiveUntil' => 1.minute.ago.iso8601)] })
    expect(instance.operating?).to be(false)
    expect(instance.deleted?).to be(false)
  end

  it 'suspends and renews the same instance without deleting its local knowledge or complements' do
    instance.update!(supplemental_instruction: 'Customer local detail.')
    entry = instance.knowledge_entries.create!(account: account, content: 'Customer local knowledge.', status: :ready)
    envelope = { 'namespace' => { 'installationId' => activation.installation_id, 'productCatalogItemId' => activation.product_catalog_item_id },
                 'accessVersion' => '1',
                 'data' => snapshot.merge('resourceRef' => activation.resource_ref, 'serviceCatalogItemId' => activation.service_catalog_item_id) }
    Autonomia::Store::Projection.apply!(envelope)
    expect(instance.operating?).to be(true)
    suspended = envelope.deep_dup
    suspended['accessVersion'] = '2'
    suspended['data']['effectiveAccess'] = 'suspended'
    suspended['data']['grants'].first['status'] = 'suspended'
    Autonomia::Store::Projection.apply!(suspended)
    expect(instance.reload.operating?).to be(false)
    Autonomia::Store::Projection.apply!(envelope) # Late callback cannot undo suspension.
    expect(instance.operating?).to be(false)
    envelope['accessVersion'] = '3'
    Autonomia::Store::Projection.apply!(envelope)
    expect(instance.reload.operating?).to be(true)
    expect(instance.supplemental_instruction).to eq('Customer local detail.')
    expect(instance.knowledge_entries.find(entry.id).content).to eq('Customer local knowledge.')
    expect(Autonomia::Agents::Agent.where(principal_agent: principal).count).to eq(1)
  end

  it 'denies access to a deleted principal without deleting the instance' do
    instance
    Autonomia::Store::Entitlement.create!(account: account, installation_id: activation.installation_id,
                                          product_catalog_item_id: activation.product_catalog_item_id,
                                          service_catalog_item_id: activation.service_catalog_item_id, payload: snapshot)
    principal.update_columns(deleted_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    expect(instance.reload.operating?).to be(false)
    expect(instance.deleted?).to be(false)
  end

  it 'prevents detaching an instance to bypass commercial access' do
    expect(instance.update(principal_agent_id: nil)).to be(false)
    expect(instance.reload.principal_agent_id).to eq(principal.id)
  end

  it 'retrieves only principal and local approved knowledge, never another tenant or rejected source' do
    foreign = Autonomia::Agents::Agent.create!(account: create(:account), name: 'Foreign', agent_type: 'custom')
    vector = Array.new(1536, 0.01)
    master_entry = principal.knowledge_entries.create!(account: owner_account, content: 'Principal fictitious stock.', embedding: vector,
                                                       status: :ready)
    own_entry = instance.knowledge_entries.create!(account: account, content: 'Local fictitious stock.', embedding: vector, status: :ready)
    foreign_entry = foreign.knowledge_entries.create!(account: foreign.account, content: 'Foreign stock.', embedding: vector, status: :ready)
    source = principal.sources.create!(account: owner_account, source_type: 'link', review_status: 'needs_review')
    rejected = principal.knowledge_entries.create!(account: owner_account, source: source, content: 'Rejected stock.', embedding: vector,
                                                   status: :ready)
    embedding = instance_double(Autonomia::Agents::EmbeddingService, embed: vector)
    expect(Autonomia::Agents::EmbeddingService).to receive(:new).with(account: account, model: anything).and_return(embedding)
    entries = Autonomia::Agents::Retriever.new(agent: instance).retrieve('stock')
    expect(entries.map(&:id)).to include(master_entry.id, own_entry.id)
    expect(entries.map(&:id)).not_to include(foreign_entry.id, rejected.id)
  end

  it 'keeps principal knowledge available when only local knowledge is disabled' do
    instance.update!(config: { 'with_knowledge' => false })
    expect(instance.knowledge_disabled?).to be(false)
    expect(instance.knowledge_agents.map(&:id)).to eq([principal.id])
  end

  it 'inherits HTTP definitions live without allowing a local same-slug override or copying secrets' do
    tool = principal.tools.create!(account: owner_account, name: 'Stock', slug: 'stock', endpoint_url: 'https://example.test/stock',
                                   headers_config: [{ key: 'x-api-key', value: 'fictitious-secret', secret: true }])
    instance.tools.create!(account: account, name: 'Local shadow', slug: 'stock', endpoint_url: 'https://example.test/shadow')
    expect(instance.effective_http_tools.map(&:id)).to eq([tool.id])
    executor = instance_double(Autonomia::Agents::Tools::HttpExecutor, call: '{"stock":5}')
    expect(Autonomia::Agents::Tools::HttpExecutor).to receive(:new).with(tool: tool, params: {}, execution_agent: instance).and_return(executor)
    bound = Autonomia::Agents::Tools::Bound.for_agent(instance).first
    expect(bound.execute({ 'arguments' => '{}' })).to eq('{"stock":5}')
    tool.update!(enabled: false)
    expect(instance.reload.effective_http_tools.map(&:id)).not_to include(tool.id)
  end

  it 'runs inherited native tools using the beneficiary account' do
    native = Class.new(Autonomia::Agents::Tools::Native::Base) do
      def self.slug = 'example_native'
      def self.description = 'Example'
      def call = account.id.to_s
    end
    principal.update!(native_tool_slugs: ['example_native'])
    expect(Autonomia::Agents::Tools::Registry).to receive(:find).with('example_native').and_return(native)
    expect(native).to receive(:available_for?).with(instance).and_return(true)
    bound = Autonomia::Agents::Tools::Bound.for_agent(instance).first
    expect(bound.execute({ 'arguments' => '{}' })).to eq(account.id.to_s)
  end

  it 'inherits delegation definitions but binds specialist tools and AI costs to the beneficiary' do
    tool = principal.tools.create!(account: owner_account, name: 'Stock', slug: 'stock', endpoint_url: 'https://example.test/stock')
    specialist = principal.specialists.create!(name: 'Stock specialist', slug: 'stock_specialist', description: 'Example stock lookup',
                                               instruction: 'Specialist procedure.', tool_slugs: ['stock'])
    bound = instance.effective_specialists.first
    expect(bound).to have_attributes(agent: instance, account: account)
    expect(bound.effective_instruction).to eq('Specialist procedure.')
    expect(bound.openai_schema[:name]).to eq(specialist.function_name)
    executor = instance_double(Autonomia::Agents::Tools::HttpExecutor, call: '{"stock":5}')
    expect(Autonomia::Agents::Tools::HttpExecutor).to receive(:new).with(tool: tool, params: {}, execution_agent: instance).and_return(executor)
    expect(bound.tools.first.execute({ 'arguments' => '{}' })).to eq('{"stock":5}')
    expect(instance.specialists).to be_empty
    specialist.update!(enabled: false)
    expect(instance.reload.effective_specialists).to be_empty
  end
end
