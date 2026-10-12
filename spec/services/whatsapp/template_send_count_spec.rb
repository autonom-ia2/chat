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

  # #1382: o envio de campanha não vira mensagem com template_params; contava zero no uso principal.
  it 'counts campaign sends accepted by Meta this month, by the campaign template, summed with conversation sends' do
    campaign = create(:campaign, account: account, inbox: inbox, template_params: { 'name' => 'renovacao', 'language' => 'pt_BR' })
    recipient = lambda do |status, sent_at|
      CampaignRecipient.create!(account: account, campaign: campaign, inbox: inbox, contact: create(:contact, account: account),
                                status: status, sent_at: sent_at)
    end
    recipient.call(:sent, now - 2.days)
    recipient.call(:delivered, now - 2.days)
    recipient.call(:read, now - 2.days)
    recipient.call(:failed, now - 2.days)
    recipient.call(:queued, nil)
    recipient.call(:skipped, nil)
    recipient.call(:delivered, Time.zone.parse('2026-09-29 10:00'))
    sent('renovacao')
    # the copy of the campaign message in the conversation (SentMessageRecorder) has no template_params: not counted twice
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, created_at: now - 2.days,
                     additional_attributes: { 'campaign_id' => campaign.id, 'campaign_template_name' => 'renovacao' })

    expect(described_class.new(account: account, inbox_ids: [inbox.id], now: now).perform).to eq(inbox.id => { 'renovacao' => 4 })
  end
end
