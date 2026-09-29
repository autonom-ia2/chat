require 'rails_helper'

RSpec.describe Crm::Ai::AttributeExtractorApplier do
  describe 'coercion compatibility after extracting the locked item loop' do
    cases = [
      ['text', '  CEO  ', 'CEO'], ['link', '  https://example.test/info  ', 'https://example.test/info'],
      ['text', nil, :invalid], ['link', '   ', :invalid], ['unknown', 42, '42'],
      ['number', '0', 0], ['currency', '10.50', 10.5], ['percent', '12', 12],
      ['date', '2026-09-29', '2026-09-29'], ['checkbox', false, false],
      ['list', 'CEO', 'CEO'], ['list', 'other', :invalid]
    ]

    cases.each do |type, input, expected|
      it "preserves #{type} coercion for #{input.inspect}" do
        definition = Struct.new(:attribute_display_type, :attribute_values).new(type, ['CEO'])
        instance = described_class.allocate
        expect(instance.send(:coerce_value, input, definition)).to eq(expected)
      end
    end
  end
end
