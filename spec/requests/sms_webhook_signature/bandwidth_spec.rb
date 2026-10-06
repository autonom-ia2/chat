require 'rails_helper'

RSpec.describe 'SMS webhook signature: Bandwidth', type: :request do
  let(:callback_config) { { 'callback_username' => 'bw-user', 'callback_password' => 'bw-pass-for-spec' } }
  let(:channel) do
    create(:channel_sms, provider_config: { 'account_id' => '1', 'application_id' => '1', 'api_key' => '1', 'api_secret' => '1' }
                                          .merge(callback_config))
  end
  let(:payload) do
    [{ type: 'message-delivered', to: channel.phone_number, message: { id: 'bw-msg-1' } }]
  end
  let(:log_lines) { [] }

  def basic(user, pass)
    ActionController::HttpAuthentication::Basic.encode_credentials(user, pass)
  end

  def post_event(headers = {})
    post "/webhooks/sms/#{channel.phone_number.delete_prefix('+')}",
         params: payload.to_json,
         headers: { 'CONTENT_TYPE' => 'application/json' }.merge(headers)
  end

  before do
    %i[info warn].each do |level|
      allow(Rails.logger).to receive(level).and_wrap_original do |original, *args, &block|
        log_lines << args.first.to_s
        original.call(*args, &block)
      end
    end
  end

  context 'when mode is enforce' do
    around { |example| with_modified_env(SMS_WEBHOOK_SIGNATURE_MODE: 'enforce') { example.run } }

    it 'processes a callback with the configured credentials' do
      expect { post_event('Authorization' => basic('bw-user', 'bw-pass-for-spec')) }
        .to have_enqueued_job(Webhooks::SmsEventsJob)
      expect(response).to have_http_status(:ok)
    end

    it 'rejects wrong credentials with 401 and a Basic challenge' do
      expect { post_event('Authorization' => basic('bw-user', 'wrong')) }.not_to have_enqueued_job(Webhooks::SmsEventsJob)
      expect(response).to have_http_status(:unauthorized)
      expect(response.headers['WWW-Authenticate']).to include('Basic')
    end

    it 'rejects a callback without credentials when the channel has them configured' do
      expect { post_event }.not_to have_enqueued_job(Webhooks::SmsEventsJob)
      expect(response).to have_http_status(:unauthorized)
    end

    it 'uses the ENV credential when the channel has none' do
      channel.update!(provider_config: channel.provider_config.except('callback_username', 'callback_password'))
      with_modified_env(BANDWIDTH_CALLBACK_USERNAME: 'env-user', BANDWIDTH_CALLBACK_PASSWORD: 'env-pass') do
        expect { post_event('Authorization' => basic('env-user', 'env-pass')) }.to have_enqueued_job(Webhooks::SmsEventsJob)
        expect { post_event('Authorization' => basic('bw-user', 'bw-pass-for-spec')) }.not_to have_enqueued_job(Webhooks::SmsEventsJob)
      end
    end

    context 'when no credential is configured anywhere' do
      let(:callback_config) { {} }

      it 'allows the callback by default and logs missing_credentials' do
        expect { post_event }.to have_enqueued_job(Webhooks::SmsEventsJob)
        expect(log_lines).to include(a_string_including('provider=bandwidth', 'result=missing_credentials', 'action=processed'))
      end

      it 'rejects it when SMS_WEBHOOK_UNVERIFIABLE_POLICY is reject' do
        with_modified_env(SMS_WEBHOOK_UNVERIFIABLE_POLICY: 'reject') do
          expect { post_event }.not_to have_enqueued_job(Webhooks::SmsEventsJob)
          expect(response).to have_http_status(:unauthorized)
        end
      end
    end
  end

  context 'when mode is log (default)' do
    it 'processes wrong credentials and logs invalid without the credential or phone' do
      expect { post_event('Authorization' => basic('bw-user', 'wrong')) }.to have_enqueued_job(Webhooks::SmsEventsJob)
      expect(response).to have_http_status(:ok)

      line = log_lines.find { |l| l.include?('[SmsWebhookSignature]') }
      expect(line).to include('result=invalid_signature', "channel_id=#{channel.id}", 'action=processed')
      ['bw-pass-for-spec', 'wrong', channel.phone_number].each { |secret| expect(line).not_to include(secret) }
    end
  end
end
