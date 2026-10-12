require 'rails_helper'

RSpec.describe Whatsapp::TemplateSendCount do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { channel.inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:now) { Time.zone.parse('2026-10-20 12:00') }

  def sent(name, **attributes)
    create(:message, { account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, created_at: now - 1.day,
                       additional_attributes: { 'template_params' => { 'name' => name } } }.merge(attributes))
  end

  it 'counts each template sent this month by inbox, without failures or last month' do
    2.times { sent('renovacao') }
    sent('boas_vindas')
    sent('renovacao', status: :failed)
    sent('renovacao', created_at: Time.zone.parse('2026-09-30 23:00'))
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, created_at: now - 1.day)

    expect(described_class.new(account: account, inbox_ids: [inbox.id], now: now).perform)
      .to eq(inbox.id => { 'renovacao' => 2, 'boas_vindas' => 1 })
  end
end
