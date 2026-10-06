require 'rails_helper'

RSpec.describe 'SMS webhook signature: Twilio', type: :request do
  let(:auth_token) { 'twilio-primary-auth-token-for-spec' }
  let(:channel) { create(:channel_twilio_sms, :with_phone_number, auth_token: auth_token, account_sid: 'ACspec') }
  let(:status_params) do
    { 'AccountSid' => 'ACspec', 'From' => channel.phone_number, 'MessageSid' => 'SMspec', 'MessageStatus' => 'delivered' }
  end
  let(:status_url) { 'http://www.example.com/twilio/delivery_status' }
  let(:log_lines) { [] }

  def signature_for(url, params, token = auth_token)
    Twilio::Security::RequestValidator.new(token).build_signature_for(url, params)
  end

  def post_status(signature:, headers: {})
    all_headers = headers.merge('X-Twilio-Signature' => signature).compact
    post '/twilio/delivery_status', params: status_params, headers: all_headers
  end

  before do
    %i[info warn].each do |level|
      allow(Rails.logger).to receive(level).and_wrap_original do |original, *args, &block|
        log_lines << args.first.to_s
        original.call(*args, &block)
      end
    end
  end

  context 'when mode is log (default)' do
    it 'processes a callback with a valid signature and logs it as valid' do
      expect { post_status(signature: signature_for(status_url, status_params)) }
        .to have_enqueued_job(Webhooks::TwilioDeliveryStatusJob)
      expect(response).to have_http_status(:no_content)
      expect(log_lines).to include(a_string_including('result=valid', "channel_id=#{channel.id}", 'action=processed'))
    end

    it 'still processes a forged callback but logs it as invalid without secrets or PII' do
      expect { post_status(signature: signature_for(status_url, status_params, 'wrong-token')) }
        .to have_enqueued_job(Webhooks::TwilioDeliveryStatusJob)
      expect(response).to have_http_status(:no_content)

      line = log_lines.find { |l| l.include?('[SmsWebhookSignature]') }
      expect(line).to include('mode=log', 'result=invalid_signature', 'action=processed')
      [auth_token, channel.phone_number, 'SMspec', 'ACspec'].each { |secret| expect(line).not_to include(secret) }
    end
  end

  context 'when mode is enforce' do
    around { |example| with_modified_env(SMS_WEBHOOK_SIGNATURE_MODE: 'enforce') { example.run } }

    it 'processes a callback with a valid signature' do
      expect { post_status(signature: signature_for(status_url, status_params)) }
        .to have_enqueued_job(Webhooks::TwilioDeliveryStatusJob)
      expect(response).to have_http_status(:no_content)
    end

    it 'rejects an invalid signature with 401 and does not process it' do
      expect { post_status(signature: signature_for(status_url, status_params, 'wrong-token')) }
        .not_to have_enqueued_job(Webhooks::TwilioDeliveryStatusJob)
      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejects a callback without the signature header' do
      expect { post_status(signature: nil) }.not_to have_enqueued_job(Webhooks::TwilioDeliveryStatusJob)
      expect(response).to have_http_status(:unauthorized)
    end

    it 'accepts the URL Twilio signed over https when TLS ends at the load balancer' do
      https_url = 'https://www.example.com/twilio/delivery_status'
      expect { post_status(signature: signature_for(https_url, status_params), headers: { 'X-Forwarded-Proto' => 'https' }) }
        .to have_enqueued_job(Webhooks::TwilioDeliveryStatusJob)
      expect(response).to have_http_status(:no_content)
    end

    it 'accepts the FRONTEND_URL based URL handed to Twilio as status_callback' do
      with_modified_env(FRONTEND_URL: 'https://app.example.org/') do
        signature = signature_for('https://app.example.org/twilio/delivery_status', status_params)
        expect { post_status(signature: signature) }.to have_enqueued_job(Webhooks::TwilioDeliveryStatusJob)
      end
    end

    it 'rejects an inbound message callback with an invalid signature' do
      inbound = { 'AccountSid' => 'ACspec', 'To' => channel.phone_number, 'From' => '+5511999990000', 'Body' => 'oi' }
      bad = signature_for('http://www.example.com/twilio/callback', inbound, 'wrong-token')

      expect { post '/twilio/callback', params: inbound, headers: { 'X-Twilio-Signature' => bad } }
        .not_to have_enqueued_job(Webhooks::TwilioEventsJob)
      expect(response).to have_http_status(:unauthorized)
    end

    it 'processes an inbound message callback with a valid signature' do
      inbound = { 'AccountSid' => 'ACspec', 'To' => channel.phone_number, 'From' => '+5511999990000', 'Body' => 'oi' }
      good = signature_for('http://www.example.com/twilio/callback', inbound)

      expect { post '/twilio/callback', params: inbound, headers: { 'X-Twilio-Signature' => good } }
        .to have_enqueued_job(Webhooks::TwilioEventsJob)
      expect(response).to have_http_status(:no_content)
    end

    context 'when the callback cannot be checked' do
      let(:channel) do
        create(:channel_twilio_sms, :with_phone_number, account_sid: 'ACspec', api_key_sid: 'SKspec', auth_token: 'api-key-secret')
      end

      it 'allows it by default and logs missing_credentials' do
        expect { post_status(signature: 'anything') }.to have_enqueued_job(Webhooks::TwilioDeliveryStatusJob)
        expect(log_lines).to include(a_string_including('result=missing_credentials', 'action=processed'))
      end

      it 'rejects it when SMS_WEBHOOK_UNVERIFIABLE_POLICY is reject' do
        with_modified_env(SMS_WEBHOOK_UNVERIFIABLE_POLICY: 'reject') do
          expect { post_status(signature: 'anything') }.not_to have_enqueued_job(Webhooks::TwilioDeliveryStatusJob)
          expect(response).to have_http_status(:unauthorized)
        end
      end
    end
  end

  context 'when mode is off' do
    around { |example| with_modified_env(SMS_WEBHOOK_SIGNATURE_MODE: 'off') { example.run } }

    it 'processes without checking or logging' do
      expect { post_status(signature: nil) }.to have_enqueued_job(Webhooks::TwilioDeliveryStatusJob)
      expect(log_lines.select { |line| line.include?('[SmsWebhookSignature]') }).to be_empty
    end
  end
end
