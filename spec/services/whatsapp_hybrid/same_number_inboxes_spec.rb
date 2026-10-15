require 'rails_helper'

# #1487: aviso de mesmo número ligado em outra caixa WhatsApp API comum (WAHA) da conta.
describe WhatsappHybrid::SameNumberInboxes do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', phone_number: '+5511999993846',
                              sync_templates: false, validate_provider_config: false)
  end
  let(:service) { described_class.new(account_id: account.id, phone: channel.reload.phone_number) }

  def waha_inbox(session, name:, target: account, provider: 'waha')
    api = Channel::Api.create!(account: target, additional_attributes: { 'provider' => provider, 'session' => session })
    create(:inbox, account: target, channel: api, name: name)
  end

  it 'lists the WhatsApp API inbox on the same number' do
    waha_inbox('5511999993846', name: 'Vendas WhatsApp')

    expect(service.names).to eq(['Vendas WhatsApp'])
  end

  it 'treats the old format without the 9 as the same number' do
    waha_inbox('551199993846', name: 'Sem o nove')

    expect(service.names).to eq(['Sem o nove'])
  end

  it 'treats the 9 as the same number when the official inbox has the old format' do
    channel.update!(phone_number: '+551199993846')
    waha_inbox('5511999993846', name: 'Com o nove')

    expect(service.names).to eq(['Com o nove'])
  end

  it 'ignores other numbers, other providers and other accounts' do
    waha_inbox('5511988887777', name: 'Outro número')
    waha_inbox('5511999993846', name: 'Evolution', provider: 'evolution')
    waha_inbox('5511999993846', name: 'Outra conta', target: create(:account))

    expect(service.names).to be_empty
  end

  it 'does not drop the 9 from numbers outside Brazil' do
    expect(described_class.canonical('+1 (415) 955-0123')).to eq('14159550123')
    expect(described_class.canonical('5511999993846')).to eq('551199993846')
  end
end
