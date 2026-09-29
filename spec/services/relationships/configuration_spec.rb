require 'rails_helper'

RSpec.describe Relationships::Configuration do
  # Reuse historical fixture metadata without introducing a pattern.
  let(:legacy_pattern) do
    File.readlines(File.expand_path('../../jobs/inboxes/update_widget_pre_chat_custom_fields_job_spec.rb', __dir__))
        .find { |line| line.include?("'regex_pattern' =>") }.split("'")[3]
  end

  let(:account) { create(:account, settings: { 'unrelated' => true }) }
  let(:service) { described_class.new(account) }
  let!(:definition) { create(:custom_attribute_definition, account: account, attribute_model: 'contact_attribute', attribute_key: 'job_title') }

  it 'distinguishes legacy from an explicitly empty selection and preserves unrelated settings' do
    expect(service.read['surfaces']).to eq({})
    service.update!({ 'revision' => 0, 'surfaces' => { 'contact_sidebar' => { 'mode' => 'custom', 'ids' => [] } } })
    expect(service.read.dig('surfaces', 'contact_sidebar', 'ids')).to eq([])
    expect(account.reload.settings['unrelated']).to be(true)
  end

  it 'rejects stale revisions without changing the layout' do
    service.update!({ 'revision' => 0, 'surfaces' => {} })
    expect { service.update!({ 'revision' => 0, 'surfaces' => {} }) }.to raise_error(Relationships::Configuration::Conflict)
    expect(service.read['revision']).to eq(1)
  end

  it 'rejects foreign IDs, wrong entities and malformed shapes' do
    foreign = create(:custom_attribute_definition, attribute_model: 'contact_attribute')
    [foreign.id, '1', -1].each do |id|
      expect do
        service.update!({ 'revision' => 0, 'surfaces' => { 'contact_sidebar' => { 'mode' => 'custom', 'ids' => [id] } } })
      end.to raise_error(Relationships::Configuration::Invalid)
    end
    expect { service.update!({ 'revision' => 0, 'surfaces' => { 'unknown' => {} } }) }.to raise_error(Relationships::Configuration::Invalid)
  end

  it 'atomically edits a legacy definition without changing its key or values' do
    contact = create(:contact, account: account, custom_attributes: { job_title: 'CEO' })
    service.update!({ 'revision' => 0, 'definition' => { 'id' => definition.id, 'revision' => definition.updated_at.iso8601(6),
                                                         'attribute_display_name' => 'Cargo', 'attribute_description' => 'Função na empresa' },
                      'surfaces' => { 'contact_details' => { 'mode' => 'custom', 'ids' => [definition.id] } } })
    expect(definition.reload.attribute_key).to eq('job_title')
    expect(contact.reload.custom_attributes['job_title']).to eq('CEO')
  end

  it 'rolls back a new definition when the layout is invalid' do
    payload = { 'revision' => 0, 'definition' => { 'attribute_display_name' => 'Cargo', 'attribute_description' => 'Função',
                                                   'attribute_key' => 'cargo', 'attribute_model' => 'contact_attribute',
                                                   'attribute_display_type' => 'text' },
                'surfaces' => { 'unknown' => { 'mode' => 'custom', 'ids' => [] } } }
    expect { service.update!(payload) }.to raise_error(Relationships::Configuration::Invalid)
    expect(account.custom_attribute_definitions.where(attribute_key: 'cargo')).not_to exist
  end

  it 'requires description for new definitions and refuses destructive edits' do
    expect do
      service.update!({ 'revision' => 0, 'definition' => { 'attribute_display_name' => 'New' } })
    end.to raise_error(Relationships::Configuration::Invalid)
    expect do
      service.update!({ 'revision' => 0, 'definition' => { 'id' => definition.id, 'revision' => definition.updated_at.iso8601(6),
                                                           'attribute_key' => 'cargo' } })
    end.to raise_error(Relationships::Configuration::Invalid)
  end

  it 'preserves opaque legacy validation metadata when renaming and rejects editable validation parameters' do
    definition.update!(regex_pattern: legacy_pattern, regex_cue: 'Historical instruction')
    before = definition.attributes.slice('regex_pattern', 'regex_cue', 'attribute_key', 'attribute_values')
    service.update!({ 'revision' => 0, 'definition' => { 'id' => definition.id, 'revision' => definition.updated_at.iso8601(6),
                                                         'attribute_display_name' => 'Cargo' } })
    expect(definition.reload.attributes.slice(*before.keys)).to eq(before)
    expect do
      service.update!({ 'revision' => 1, 'definition' => { 'attribute_display_name' => 'New', 'regex_pattern' => legacy_pattern } })
    end.to raise_error(Relationships::Configuration::Invalid)
    expect(account.reload.settings.dig('relationships', 'revision')).to eq(1)
  end
end
