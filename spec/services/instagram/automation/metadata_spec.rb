require 'rails_helper'

RSpec.describe Instagram::Automation::Metadata do
  subject(:metadata) { described_class.new }

  let(:values) do
    {
      'INSTAGRAM_META_DEVELOPER_APP_ID' => '10001',
      'INSTAGRAM_META_BUSINESS_ID' => '10002',
      'INSTAGRAM_TESTER_APP_NAME' => 'Synthetic App',
      'INSTAGRAM_TESTER_ADMIN_USER_ID' => '10003',
      'INSTAGRAM_TESTER_ROLES_DOC_ID' => '10004'
    }
  end

  it 'reads ENV only for absent records without creating any' do
    with_modified_env(values) do
      expect { expect(metadata.values).to eq(values) }.not_to change(InstallationConfig, :count)
    end
  end

  it 'uses saved values including empty strings instead of ENV' do
    create(:installation_config, name: 'INSTAGRAM_META_DEVELOPER_APP_ID', value: '')
    create(:installation_config, name: 'INSTAGRAM_TESTER_APP_NAME', value: 'Saved App')
    with_modified_env(values) do
      expect(metadata.values).to eq(values.merge('INSTAGRAM_META_DEVELOPER_APP_ID' => '', 'INSTAGRAM_TESTER_APP_NAME' => 'Saved App'))
    end
  end

  it 'saves only the five nonsecret fields and permits clearing them' do
    metadata.update!(values)
    expect(InstallationConfig.where(name: values.keys).count).to eq(5)
    metadata.update!(values.transform_values { '' })
    expect(metadata.values.values).to all(eq(''))
  end

  it 'preserves omitted fields' do
    metadata.update!(values)
    metadata.update!('INSTAGRAM_TESTER_APP_NAME' => 'Updated')
    expect(metadata.values).to eq(values.merge('INSTAGRAM_TESTER_APP_NAME' => 'Updated'))
  end

  it 'rejects invalid IDs, types, whitespace names and unknown keys before any write' do
    [
      { 'INSTAGRAM_META_BUSINESS_ID' => '12x' },
      { 'INSTAGRAM_META_BUSINESS_ID' => '1' * 41 },
      { 'INSTAGRAM_META_BUSINESS_ID' => 123 },
      { 'INSTAGRAM_META_BUSINESS_ID' => ' 123' },
      { 'INSTAGRAM_META_BUSINESS_ID' => '123\n' },
      { 'INSTAGRAM_META_BUSINESS_ID' => '１２３' },
      { 'INSTAGRAM_TESTER_APP_NAME' => '  ' },
      { 'INSTAGRAM_TESTER_APP_NAME' => ' App' },
      { 'INSTAGRAM_TESTER_APP_NAME' => "App\u00a0" },
      { 'INSTAGRAM_TESTER_APP_NAME' => 'a' * 121 },
      { 'INSTAGRAM_TESTER_APP_NAME' => "App\nname" },
      { 'INSTAGRAM_TESTER_APP_NAME' => "App\u0000name" },
      { 'INSTAGRAM_TESTER_APP_NAME' => "App\u007fname" },
      { 'INSTAGRAM_TESTER_APP_NAME' => "App\u202ename" },
      { 'INSTAGRAM_TESTER_APP_NAME' => nil },
      { 'INSTAGRAM_TESTER_SESSION_JSON' => 'synthetic-secret' },
      { 'INSTAGRAM_TESTER_AUTOMATION_ENABLED' => 'true' }
    ].each do |invalid|
      expect { metadata.update!(values.merge(invalid)) }.to raise_error(described_class::InvalidConfiguration)
      expect(InstallationConfig.where(name: values.keys)).to be_empty
    end
  end

  it 'accepts the exact 120 character limit and preserves exact string IDs' do
    metadata.update!(values.merge('INSTAGRAM_TESTER_APP_NAME' => 'á' * 120, 'INSTAGRAM_META_BUSINESS_ID' => '000123'))

    expect(metadata.values.fetch('INSTAGRAM_TESTER_APP_NAME')).to eq('á' * 120)
    expect(metadata.values.fetch('INSTAGRAM_META_BUSINESS_ID')).to eq('000123')
  end

  it 'reads a single snapshot and derives the canonical nonsecret revision from it' do
    metadata.update!(values.to_a.reverse.to_h)
    expect(InstallationConfig).to receive(:where).with(name: described_class::KEYS).once.and_call_original

    expect(metadata.values).to eq(values)
    expect(metadata.revision).to eq(Digest::SHA256.hexdigest(values.to_json))
    expect(metadata.values).to be_frozen
  end

  it 'keeps one read snapshot while a later operation observes committed changes' do
    metadata.update!(values)
    expect(metadata.values).to eq(values)
    described_class.new.update!('INSTAGRAM_TESTER_APP_NAME' => 'Later App')

    expect(metadata.values).to eq(values)
    expect(described_class.new.values).to eq(values.merge('INSTAGRAM_TESTER_APP_NAME' => 'Later App'))
  end

  it 'rolls back all changes if a save fails' do
    metadata.update!(values)
    failing_config = InstallationConfig.find_by!(name: 'INSTAGRAM_META_BUSINESS_ID')
    allow(InstallationConfig).to receive(:find_or_initialize_by).and_call_original
    allow(InstallationConfig).to receive(:find_or_initialize_by).with(name: failing_config.name).and_return(failing_config)
    allow(failing_config).to receive(:save!).and_raise(ActiveRecord::RecordInvalid, failing_config)
    expect { metadata.update!(values.transform_values { '' }) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(metadata.values).to eq(values)
  end
end
