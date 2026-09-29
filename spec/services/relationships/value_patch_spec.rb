require 'rails_helper'

RSpec.describe Relationships::ValuePatch do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, custom_attributes: { 'untouched' => 'keep' }) }
  let(:definition) do
    create(:custom_attribute_definition, account: account, attribute_model: 'contact_attribute', attribute_key: 'value', attribute_display_type: type)
  end
  let(:type) { 'number' }

  before { definition }

  it 'saves zero and clears empty numbers without replacing hidden values' do
    described_class.new(contact, 'contact_attribute').update!({ 'key' => 'value', 'value' => 0, 'previous' => nil })
    expect(contact.reload.custom_attributes).to include('value' => 0, 'untouched' => 'keep')
    described_class.new(contact, 'contact_attribute').update!({ 'key' => 'value', 'value' => nil, 'previous' => 0 })
    expect(contact.reload.custom_attributes).to eq('untouched' => 'keep')
  end

  it 'rejects stale edits and coercion' do
    expect { described_class.new(contact, 'contact_attribute').update!({ 'key' => 'value', 'value' => '0', 'previous' => nil }) }
      .to raise_error(Relationships::Configuration::Invalid)
    contact.update!(custom_attributes: { 'value' => 7 })
    expect { described_class.new(contact, 'contact_attribute').update!({ 'key' => 'value', 'value' => 2, 'previous' => nil }) }
      .to raise_error(Relationships::Configuration::Conflict)
  end

  context 'with checkbox' do
    let(:type) { 'checkbox' }

    it 'preserves false' do
      described_class.new(contact, 'contact_attribute').update!({ 'key' => 'value', 'value' => false, 'previous' => nil })
      expect(contact.reload.custom_attributes['value']).to be(false)
    end
  end

  context 'with date' do
    let(:type) { 'date' }

    it 'stores date-only and rejects invalid calendar dates' do
      described_class.new(contact, 'contact_attribute').update!({ 'key' => 'value', 'value' => '2026-09-29', 'previous' => nil })
      expect(contact.reload.custom_attributes['value']).to eq('2026-09-29')
      expect { described_class.new(contact, 'contact_attribute').update!({ 'key' => 'value', 'value' => '2026-02-30', 'previous' => '2026-09-29' }) }
        .to raise_error(Relationships::Configuration::Invalid)
    end
  end
end
