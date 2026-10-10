require 'rails_helper'

# Amostras reais do spike F0 (06/10/2026): o id do WAHA vem dentro do wamid do eco.
describe WhatsappHybrid::Wamid do
  it 'reads the WhatsApp message id from an echo addressed to a BSUID' do
    wamid = 'wamid.HBgTQlIuMTM3NzQ0NTI1NDIyMjE2MhUUABEYFjNFQjA2QjI0NjZFN0VGQkFCMkRFNzkA'

    expect(described_class.message_id(wamid)).to eq('3EB06B2466E7EFBAB2DE79')
  end

  it 'reads the message id from a phone-addressed wamid' do
    wamid = 'wamid.HBgNNTUxMTkzNzAxNjA5NBUCABIYFDJBNUQyRDhEQTA4OUJFNDJFNEQ1AA=='

    expect(described_class.message_id(wamid)).to eq('2A5D2D8DA089BE42E4D5')
  end

  it 'returns nil for ids that are not wamids' do
    expect(described_class.message_id('3EB06B2466E7EFBAB2DE79')).to be_nil
    expect(described_class.message_id(nil)).to be_nil
    expect(described_class.message_id('wamid.')).to be_nil
  end
end
