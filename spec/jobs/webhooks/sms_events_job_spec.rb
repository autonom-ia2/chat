require 'rails_helper'

RSpec.describe Webhooks::SmsEventsJob do
  subject(:job) { described_class.perform_later(params) }

  let!(:sms_channel) { create(:channel_sms) }
  let!(:params) do
    {
      time: '2022-02-02T23:14:05.309Z',
      type: 'message-received',
      to: sms_channel.phone_number,
      description: 'Incoming message received',
      message: {
        'id': '3232420-2323-234324',
        'owner': sms_channel.phone_number,
        'applicationId': '2342349-324234d-32432432',
        'time': '2022-02-02T23:14:05.262Z',
        'segmentCount': 1,
        'direction': 'in',
        'to': [
          sms_channel.phone_number
        ],
        'from': '+14234234234',
        'text': 'test message'
      }
    }
  end

  it 'enqueues the job' do
    expect { job }.to have_enqueued_job(described_class)
      .with(params)
      .on_queue('default')
  end

  context 'when invalid params' do
    it 'returns nil when no bot_token' do
      expect(described_class.perform_now({})).to be_nil
    end

    it 'returns nil when invalid type' do
      expect(described_class.perform_now({ type: 'invalid' })).to be_nil
    end
  end

  context 'when valid params' do
    it 'calls Sms::IncomingMessageService if the message type is message-received' do
      process_service = double
      allow(Sms::IncomingMessageService).to receive(:new).and_return(process_service)
      allow(process_service).to receive(:perform)
      expect(Sms::IncomingMessageService).to receive(:new).with(inbox: sms_channel.inbox,
                                                                params: params[:message].with_indifferent_access)
      expect(process_service).to receive(:perform)
      described_class.perform_now(params)
    end

    it 'calls Sms::DeliveryStatusService if the message type is message-delivered' do
      params[:type] = 'message-delivered'
      create(:message, account: sms_channel.account, inbox: sms_channel.inbox, source_id: params[:message][:id]) # #1004: the inbox holds the id
      process_service = double
      allow(Sms::DeliveryStatusService).to receive(:new).and_return(process_service)
      allow(process_service).to receive(:perform)
      # #1004 (fork): the delivery event reaches the service with the inbox and the whole event.
      expect(Sms::DeliveryStatusService).to receive(:new).with(inbox: sms_channel.inbox, params: params.with_indifferent_access)
      expect(process_service).to receive(:perform)
      described_class.perform_now(params)
    end

    it 'calls Sms::DeliveryStatusService if the message type is message-failed' do
      params[:type] = 'message-failed'
      create(:message, account: sms_channel.account, inbox: sms_channel.inbox, source_id: params[:message][:id]) # #1004: the inbox holds the id
      process_service = double
      allow(Sms::DeliveryStatusService).to receive(:new).and_return(process_service)
      allow(process_service).to receive(:perform)
      # #1004 (fork): the delivery event reaches the service with the inbox and the whole event.
      expect(Sms::DeliveryStatusService).to receive(:new).with(inbox: sms_channel.inbox, params: params.with_indifferent_access)
      expect(process_service).to receive(:perform)
      described_class.perform_now(params)
    end

    it 'does not call any service if the message type is not supported' do
      params[:type] = 'message-sent'
      expect(Sms::IncomingMessageService).not_to receive(:new)
      expect(Sms::DeliveryStatusService).not_to receive(:new)
      described_class.perform_now(params)
    end
  end
end
