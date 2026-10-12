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

  it 'counts the free replies of this month, without templates, notes, failures or incoming messages' do
    2.times { message }
    message(additional_attributes: { 'template_params' => { 'name' => 'renovacao' } })
    message(private: true)
    message(status: :failed)
    message(message_type: :incoming)
    message(created_at: Time.zone.parse('2026-09-30 23:00'))

    expect(described_class.new(account: account, inbox_ids: [inbox.id], now: now).perform).to eq(inbox.id => 2)
  end

  it 'answers 0 for a number that sent nothing' do
    other = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)

    expect(described_class.new(account: account, inbox_ids: [other.inbox.id], now: now).perform).to eq(other.inbox.id => 0)
  end
end
