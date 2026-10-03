require 'rails_helper'

RSpec.describe Instagram::Testers::Validation do
  describe '.normalize_username' do
    it 'normalizes one leading @, whitespace and case' do
      expect(described_class.normalize_username('  @Demo_Company.1  ')).to eq('demo_company.1')
    end

    [nil, 123, [], {}, '', 'a' * 31, '@@demo', 'demo/user', 'ação', "demo\nuser"].each do |value|
      it "rejects invalid username #{value.inspect}" do
        expect { described_class.normalize_username(value) }.to raise_error do |error|
          expect(error.class.name).to eq('Instagram::Testers::Error')
          expect(error.code).to eq('invalid_username')
        end
      end
    end
  end

  it 'requires source identifiers as digit strings without numeric coercion' do
    expect(described_class.id?('17841400000000001')).to be true
    expect(described_class.id?(17_841_400_000_000_001)).to be false
    expect(described_class.id?('17e3')).to be false
  end
end
