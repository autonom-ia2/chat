require 'spec_helper'
require_relative '../../../../config/environment'

RSpec.describe Instagram::Automation::SessionPublisher do
  subject(:publisher) { described_class.new }

  let(:control) { instance_double(Instagram::Automation::OperatorControl) }
  let(:id) { SecureRandom.uuid }
  let(:envelope) { { 'type' => 'operator', 'manager' => nil, 'request' => nil } }

  it 'accepts only the four allowlisted operator operations without opening session storage' do
    allow(Instagram::Automation::OperatorControl).to receive(:new).and_return(control)
    expect(Instagram::Testers::SessionStore).not_to receive(:new)
    expect(control).to receive(:heartbeat).with(request_id: nil, state: 'operator_required', control_available: true).and_return(envelope)
    expect(control).to receive(:read).exactly(3).times.and_return(envelope)
    expect(control).to receive(:claim).with(id)
    expect(control).to receive(:complete).with(id, 'operator_required')
    [
      { 'operation' => 'manager_heartbeat', 'state' => 'operator_required', 'control_available' => true },
      { 'operation' => 'operator_read' }, { 'operation' => 'operator_claim', 'id' => id },
      { 'operation' => 'operator_complete', 'id' => id, 'state' => 'operator_required' }
    ].each { |request| expect(publisher.call(request.merge('type' => 'operator'))).to eq(envelope) }
  end

  it 'rejects malformed types, extra fields, arbitrary commands and client-supplied success before storage' do
    expect(Instagram::Automation::OperatorControl).not_to receive(:new)
    [nil, [], { 'operation' => 'version' }, { 'type' => 'operator', 'operation' => 'exec' },
     { 'type' => 'operator', 'operation' => 'operator_read', 'cookie' => 'synthetic' },
     { 'type' => 'operator', 'operation' => 'operator_claim', 'id' => '../invalid' },
     { 'type' => 'operator', 'operation' => 'operator_complete', 'id' => id, 'state' => 'succeeded' },
     { 'type' => 'session', 'operation' => 'invalidate', 'expected_version' => id }].each do |request|
      expect { publisher.call(request) }.to raise_error(Instagram::Automation::OperatorControl::Rejected, 'operator_channel_unavailable')
    end
  end

  context 'with canonical saved metadata' do
    let(:metadata) do
      { 'INSTAGRAM_META_DEVELOPER_APP_ID' => '10001', 'INSTAGRAM_META_BUSINESS_ID' => '10002',
        'INSTAGRAM_TESTER_APP_NAME' => 'Synthetic App', 'INSTAGRAM_TESTER_ADMIN_USER_ID' => '12345',
        'INSTAGRAM_TESTER_ROLES_DOC_ID' => '10003' }
    end
    let(:revision) { Digest::SHA256.hexdigest(metadata.to_json) }
    let(:relation) { instance_double(ActiveRecord::Relation) }
    let(:configuration) do
      instance_double(Instagram::Testers::Configuration, managed_session?: true,
                                                         proxy: instance_double(Instagram::Testers::Proxy, valid?: true, fingerprint: 'a' * 64))
    end
    let(:store) { instance_double(Instagram::Testers::SessionStore, current_version: nil) }
    let(:request) do
      { 'type' => 'session', 'operation' => 'publish', 'session' => { 'user_id' => '12345' }, 'expected_version' => nil,
        'captured_at' => Time.current.iso8601, 'app_id' => '10001', 'business_id' => '10002',
        'proxy_fingerprint' => 'a' * 64, 'roles_response' => '{}', 'request_id' => id,
        'configuration_revision' => revision, 'roles_doc_id' => '10003' }
    end

    before do
      allow(InstallationConfig).to receive(:transaction).and_yield
      allow(InstallationConfig).to receive(:where).with(name: Instagram::Automation::Metadata::KEYS).and_return(relation)
      allow(relation).to receive(:reorder).with(:name).and_return(relation)
      allow(relation).to receive(:lock).and_return(relation)
      allow(relation).to receive(:to_a) { metadata.map { |key, value| Struct.new(:name, :value).new(key, value) } }
      allow(Instagram::Testers::Configuration).to receive(:new).and_return(configuration)
      allow(Instagram::Testers::SessionStore).to receive(:new).and_return(store)
      allow(Instagram::Automation::OperatorControl).to receive(:new).and_return(control)
      allow(control).to receive(:with_publication).with(id) { |_, &block| block.call }
      allow(Instagram::Testers::ResponseParser).to receive(:parse).and_return({})
      allow(Instagram::Testers::ResponseParser).to receive(:status)
    end

    it 'bootstraps all five saved values and the CAS version read only, ignoring old ENV IDs' do
      with_modified_env('INSTAGRAM_META_DEVELOPER_APP_ID' => '99999') do
        expect(store).not_to receive(:publish)
        expect(control).not_to receive(:with_publication)
        expect(publisher.call('type' => 'session', 'operation' => 'bootstrap')).to eq(type: 'bootstrap', metadata: metadata,
                                                                                      revision: revision, version: nil)
      end
    end

    it 'holds the metadata transaction and row locks across actual session publication' do
      inside = false
      allow(InstallationConfig).to receive(:transaction) { |&block|
        inside = true
        result = block.call
        inside = false
        result
      }
      expect(relation).to receive(:reorder).with(:name).ordered.and_return(relation)
      expect(relation).to receive(:lock).ordered.and_return(relation)
      version = SecureRandom.uuid
      expect(store).to receive(:publish).ordered do
        expect(inside).to be(true)
        version
      end
      expect(publisher.call(request)).to eq(type: 'session', version: version)
    end

    it 'accepts the current Meta app-context response only for the configured app' do
      version = SecureRandom.uuid
      allow(Instagram::Testers::ResponseParser).to receive(:parse)
        .and_return({ 'data' => { 'fetch__Application' => { 'id' => '10001' } } })
      expect(Instagram::Testers::ResponseParser).not_to receive(:status)
      expect(store).to receive(:publish).and_return(version)

      expect(publisher.call(request)).to eq(type: 'session', version: version)
    end

    it 'rejects a current Meta app-context response for another app before storage' do
      allow(Instagram::Testers::ResponseParser).to receive(:parse)
        .and_return({ 'data' => { 'fetch__Application' => { 'id' => '99999' } } })
      expect(Instagram::Testers::ResponseParser).not_to receive(:status)
      expect(store).not_to receive(:publish)

      expect { publisher.call(request) }.to raise_error(Instagram::Testers::Error, 'unknown_status')
    end

    it 'rejects changes of App, business, admin, doc or name between bootstrap and publish before CAS' do
      old_revision = revision
      metadata.keys.each do |key|
        original = metadata.fetch(key)
        metadata[key] = key == 'INSTAGRAM_TESTER_APP_NAME' ? 'New App' : '99999'
        expect(store).not_to receive(:publish)
        expect { publisher.call(request.merge('configuration_revision' => old_revision)) }.to raise_error(Instagram::Testers::Error)
        metadata[key] = original
      end
    end

    it 'pins SessionStore to the locked App/admin/proxy snapshot' do
      expect(Instagram::Testers::SessionStore).to receive(:new) do |configuration:|
        expect(configuration.app_id).to eq('10001')
        expect(configuration.admin_user_id).to eq('12345')
        expect(configuration.proxy_fingerprint).to eq('a' * 64)
        store
      end
      publisher.call('type' => 'session', 'operation' => 'bootstrap')
    end

    it 'does not report success on CAS or claim failure' do
      allow(store).to receive(:publish).and_raise(Instagram::Testers::Error, 'session_update_rejected')
      expect { publisher.call(request) }.to raise_error(Instagram::Testers::Error)
      allow(control).to receive(:with_publication).and_raise(Instagram::Automation::OperatorControl::Rejected)
      expect(store).not_to receive(:publish)
      expect { publisher.call(request) }.to raise_error(Instagram::Automation::OperatorControl::Rejected)
    end

    it 'rejects missing, unbounded or invalid metadata instead of falling back to ENV' do
      key = 'INSTAGRAM_TESTER_APP_NAME'
      ['x' * 121, ' bad', "bad\nname", '', 123].each do |invalid|
        metadata[key] = invalid
        expect { publisher.call('type' => 'session', 'operation' => 'bootstrap') }.to raise_error(Instagram::Testers::Error)
      end
      metadata.delete(key)
      expect { publisher.call('type' => 'session', 'operation' => 'bootstrap') }.to raise_error(Instagram::Testers::Error)
    end

    it 'requires the captured roles document ID and the revision on publish' do
      expect(store).not_to receive(:publish)
      expect { publisher.call(request.merge('roles_doc_id' => '99999')) }.to raise_error(Instagram::Testers::Error)
      expect { publisher.call(request.except('configuration_revision')) }.to raise_error(Instagram::Automation::OperatorControl::Rejected)
    end
  end
end
