require 'rails_helper'

RSpec.describe Whatsapp::ServiceMessageCount do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { channel.inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:now) { Time.zone.parse('2026-10-20 12:00') }

  def message(**attributes)
    create(:message, { account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                       created_at: now - 1.day }.merge(attributes))
  end

  def count
    described_class.new(account: account, inbox_ids: [inbox.id], now: now).perform
  end

  # O fuso da WABA tem spec próprio (waba_timezone_spec); aqui, sem ele, vale o fuso da conta (UTC na fábrica).
  before { allow(Whatsapp::WabaTimezone).to receive(:for).and_return(nil) }

  it 'counts the free replies of this month, without templates, notes, failures or incoming messages' do
    2.times { message }
    message(additional_attributes: { 'template_params' => { 'name' => 'renovacao' } })
    message(private: true)
    message(status: :failed)
    message(message_type: :incoming)
    message(created_at: Time.zone.parse('2026-09-30 23:00 UTC'))

    expect(count).to eq(inbox.id => 2)
  end

  it 'answers 0 for a number that sent nothing' do
    other = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)

    expect(described_class.new(account: account, inbox_ids: [other.inbox.id], now: now).perform).to eq(other.inbox.id => 0)
  end

  it 'turns the month at midnight in the WABA timezone' do
    allow(Whatsapp::WabaTimezone).to receive(:for).with(channel).and_return(ActiveSupport::TimeZone['America/Sao_Paulo'])
    message(created_at: Time.zone.parse('2026-10-01 02:00 UTC')) # 30/09, 23:00 em São Paulo
    message(created_at: Time.zone.parse('2026-10-01 03:30 UTC')) # 01/10, 00:30 em São Paulo

    expect(count).to eq(inbox.id => 1)
  end

  it 'uses the account timezone when the WABA timezone is unknown' do
    account.update!(reporting_timezone: 'Asia/Tokyo')
    allow(Whatsapp::WabaTimezone).to receive(:for).and_return(nil)
    message(created_at: Time.zone.parse('2026-09-30 16:00 UTC')) # 01/10, 01:00 em Tóquio

    expect(count).to eq(inbox.id => 1)
  end

  it 'does not count a reaction sent from the WhatsApp app (coexistence echo), but counts a text echo' do
    echo = lambda do |id, body|
      { phone_number: channel.phone_number, object: 'whatsapp_business_account',
        entry: [{ changes: [{ field: 'smb_message_echoes', value: { message_echoes: [{
          from: channel.phone_number.delete('+'), to: '5511999990000', id: id, timestamp: Time.current.to_i.to_s
        }.merge(body)] } }] }] }.with_indifferent_access
    end

    [echo.call('wamid.echo-text', type: 'text', text: { body: 'oi' }),
     echo.call('wamid.echo-reaction', type: 'reaction', reaction: { message_id: 'wamid.echo-text', emoji: '+1' })].each do |params|
      Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: inbox, params: params, outgoing_echo: true).perform
    end

    expect(described_class.new(account: account, inbox_ids: [inbox.id], now: Time.current).perform).to eq(inbox.id => 1)
  end
end
