require 'rails_helper'

RSpec.describe Instagram::Testers::Configuration do
  subject(:configuration) { described_class.new(account_id: 1) }

  let(:metadata) { Instagram::Automation::Metadata.new }
  let(:environment) do
    {
      'INSTAGRAM_META_DEVELOPER_APP_ID' => '10001',
      'INSTAGRAM_META_BUSINESS_ID' => '10002',
      'INSTAGRAM_TESTER_ROLES_DOC_ID' => '10003',
      'INSTAGRAM_TESTER_ADMIN_USER_ID' => '10004',
      'INSTAGRAM_TESTER_APP_NAME' => 'Environment App',
      'INSTAGRAM_TESTER_SESSION_SOURCE' => 'env'
    }
  end

  around { |example| with_modified_env(environment) { example.run } }

  after { GlobalConfig.clear_cache(*Instagram::Automation::Metadata::KEYS, 'UNRELATED_ECHO') }

  {
    app_id: 'INSTAGRAM_META_DEVELOPER_APP_ID',
    business_id: 'INSTAGRAM_META_BUSINESS_ID',
    doc_id: 'INSTAGRAM_TESTER_ROLES_DOC_ID',
    admin_user_id: 'INSTAGRAM_TESTER_ADMIN_USER_ID',
    app_name: 'INSTAGRAM_TESTER_APP_NAME'
  }.each do |accessor, key|
    describe "##{accessor}" do
      it 'uses the saved value instead of ENV' do
        metadata.update!(key => '20001')

        expect(configuration.public_send(accessor)).to eq('20001')
        expect(Instagram::Automation::LocalStatus.new.call[:config_complete]).to be true
      end

      it 'keeps a saved empty value and makes local status incomplete despite valid ENV' do
        metadata.update!(key => '')

        expect(configuration.public_send(accessor)).to eq('')
        expect(Instagram::Automation::LocalStatus.new.call[:config_complete]).to be false
      end

      it 'falls back to ENV only when the record is absent, without creating it' do
        expect do
          expect(configuration.public_send(accessor)).to eq(environment.fetch(key))
          expect(Instagram::Automation::LocalStatus.new.call[:config_complete]).to be true
        end.not_to change(InstallationConfig, :count)
      end
    end
  end

  it 'uses the exact service values, including nil in an existing record' do
    create(:installation_config, name: 'INSTAGRAM_META_DEVELOPER_APP_ID', value: nil)

    expect(configuration.app_id).to be_nil
    expect(metadata.values.fetch('INSTAGRAM_META_DEVELOPER_APP_ID')).to be_nil
    expect(Instagram::Automation::LocalStatus.new.call[:config_complete]).to be false
  end

  it 'keeps the operation snapshot consistent and updates new readers and local status after saving' do
    key = 'INSTAGRAM_META_DEVELOPER_APP_ID'
    metadata.update!(key => '20001')
    expect(configuration.app_id).to eq('20001')
    expect(Instagram::Automation::LocalStatus.new.call[:config_complete]).to be true

    metadata.update!(key => '')

    expect(configuration.app_id).to eq('20001')
    expect(described_class.new(account_id: 1).app_id).to eq('')
    expect(Instagram::Automation::LocalStatus.new.call[:config_complete]).to be false
  end

  it 'performs one metadata query for all five accessors in an operation' do
    expect(InstallationConfig).to receive(:where).with(name: Instagram::Automation::Metadata::KEYS).once.and_call_original

    expect(configuration.app_id).to eq(environment.fetch('INSTAGRAM_META_DEVELOPER_APP_ID'))
    expect(configuration.business_id).to eq(environment.fetch('INSTAGRAM_META_BUSINESS_ID'))
    expect(configuration.doc_id).to eq(environment.fetch('INSTAGRAM_TESTER_ROLES_DOC_ID'))
    expect(configuration.admin_user_id).to eq(environment.fetch('INSTAGRAM_TESTER_ADMIN_USER_ID'))
    expect(configuration.app_name).to eq(environment.fetch('INSTAGRAM_TESTER_APP_NAME'))
  end

  it 'invalidates only the saved key cache' do
    key = 'INSTAGRAM_META_DEVELOPER_APP_ID'
    prefix = "#{GlobalConfig::VERSION}:#{GlobalConfig::KEY_PREFIX}"
    redis = Redis::Alfred.with { |connection| connection }
    metadata.update!(key => '20001')
    expect(GlobalConfig.get_value(key)).to eq('20001')
    redis.set("#{prefix}:UNRELATED_ECHO", { value: 'keep' }.to_json)
    allow(redis).to receive(:keys).and_call_original
    allow(redis).to receive(:scan).and_call_original

    metadata.update!(key => '')

    expect(redis.get("#{prefix}:#{key}")).to be_nil
    expect(GlobalConfig.get_value('UNRELATED_ECHO')).to eq('keep')
    expect(GlobalConfig.get_value(key)).to eq('')
    expect(redis).not_to have_received(:keys)
    expect(redis).not_to have_received(:scan)
  end
end
