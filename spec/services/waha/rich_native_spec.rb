require 'rails_helper'

# chat#1709: o que é comum ao envio nativo pelo motor (Híbrido e, na fase 2, a caixa WAHA comum).
RSpec.describe Waha::RichNative do
  describe '.row_id and .split_row_id' do
    it 'joins the option and the message with the fixed separator, and splits by the LAST one' do
      expect(described_class.row_id('manha', 123, max: 200)).to eq('manha|123')
      expect(described_class.split_row_id('manha|123')).to eq(['manha', 123])
      expect(described_class.split_row_id('a|b|123')).to eq(['a|b', 123])
    end

    it 'keeps the row id whole when there is no numeric reference' do
      expect(described_class.row_id('manha', nil, max: 200)).to eq('manha')
      expect(described_class.row_id('manha', 123, max: 8)).to eq('manha')
      expect(described_class.split_row_id('manha')).to eq(['manha', nil])
      expect(described_class.split_row_id('manha|tarde')).to eq(['manha|tarde', nil])
      expect(described_class.split_row_id('|123')).to eq(['|123', nil])
    end
  end
end
