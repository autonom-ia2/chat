require 'rails_helper'

# #1487: aviso de mesmo número ligado em outra caixa WhatsApp API comum (WAHA) da conta, só com a sessão viva no motor.
describe WhatsappHybrid::SameNumberInboxes do
  let(:account) { create(:account) }
  let(:client) { instance_double(Waha::Client) }
  let(:service) { described_class.new(account_id: account.id, phone: '+5511999993846', client: client) }
  let(:engine) { [] }

  before { allow(client).to receive(:list_sessions) { engine } }

  def waha_inbox(session, name:, target: account, provider: 'waha')
    api = Channel::Api.create!(account: target, additional_attributes: { 'provider' => provider, 'session' => session })
    create(:inbox, account: target, channel: api, name: name)
  end

  def live(name, status: 'WORKING', phone: nil)
    { 'name' => name, 'status' => status, 'me' => (phone && { 'id' => "#{phone}@c.us" }) }.compact
  end

  it 'lists the WhatsApp API inbox whose live session is on the same number' do
    waha_inbox('5511999993846', name: 'Vendas WhatsApp')
    engine << live('5511999993846', phone: '5511999993846')

    expect(service.names).to eq(['Vendas WhatsApp'])
  end

  it 'treats the old format without the 9 as the same number' do
    waha_inbox('551199993846', name: 'Sem o nove')
    engine << live('551199993846', status: 'SCAN_QR_CODE')

    expect(service.names).to eq(['Sem o nove'])
  end

  it 'compares by the phone the engine reports, for migrated sessions with another name' do
    waha_inbox('comercial-antigo', name: 'Migrada')
    engine << live('comercial-antigo', status: 'STARTING', phone: '551199993846')

    expect(service.names).to eq(['Migrada'])
  end

  it 'does not warn about an old inbox whose session is stopped, failed or gone from the engine' do
    waha_inbox('5511999993846', name: 'Parada')
    waha_inbox('551199993846', name: 'Apagada no motor')
    engine << live('5511999993846', status: 'STOPPED')

    expect(service.names).to be_empty
  end

  it 'ignores other numbers, other providers and other accounts' do
    waha_inbox('5511988887777', name: 'Outro número')
    waha_inbox('5511999993846', name: 'Evolution', provider: 'evolution')
    waha_inbox('5511999993846', name: 'Outra conta', target: create(:account))
    engine.push(live('5511988887777'), live('5511999993846'))

    expect(service.names).to be_empty
  end

  it 'shows no warning when the engine does not answer' do
    waha_inbox('5511999993846', name: 'Vendas WhatsApp')
    allow(client).to receive(:list_sessions).and_raise(Waha::Client::Timeout, 'timeout')

    expect(service.names).to be_empty
  end

  it 'does not ask the engine when the account has no WhatsApp API inbox' do
    expect(service.names).to be_empty
    expect(client).not_to have_received(:list_sessions)
  end

  describe '.canonical' do
    it 'drops the extra 9 only before a mobile digit (6 to 9)' do
      expect(described_class.canonical('5511999993846')).to eq('551199993846')
      expect(described_class.canonical('5511969993846')).to eq('551169993846')
      expect(described_class.canonical('5511953334444')).to eq('5511953334444')
    end

    it 'keeps numbers outside Brazil as they are' do
      expect(described_class.canonical('+1 (415) 955-0123')).to eq('14159550123')
    end
  end
end
