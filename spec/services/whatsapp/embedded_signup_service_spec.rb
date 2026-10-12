require 'rails_helper'

describe Whatsapp::EmbeddedSignupService do
  let(:account) { create(:account) }
  let(:params) do
    {
      code: 'test_authorization_code',
      business_id: 'test_business_id',
      waba_id: 'test_waba_id',
      phone_number_id: 'test_phone_number_id'
    }
  end
  let(:service) { described_class.new(account: account, params: params) }
  let(:access_token) { 'test_access_token' }
  let(:phone_info) do
    {
      phone_number_id: params[:phone_number_id],
      phone_number: '+1234567890',
      verified: true,
      business_name: 'Test Business'
    }
  end
  let(:channel) { instance_double(Channel::Whatsapp) }

  describe '#perform' do
    before do
      allow(GlobalConfig).to receive(:clear_cache)

      # Mock service dependencies
      token_exchange = instance_double(Whatsapp::TokenExchangeService)
      allow(Whatsapp::TokenExchangeService).to receive(:new).with(params[:code]).and_return(token_exchange)
      allow(token_exchange).to receive(:perform).and_return(access_token)

      phone_service = instance_double(Whatsapp::PhoneInfoService)
      allow(Whatsapp::PhoneInfoService).to receive(:new)
        .with(params[:waba_id], params[:phone_number_id], access_token, expected_phone_number: anything).and_return(phone_service)
      allow(phone_service).to receive(:perform).and_return(phone_info)

      channel_creation = instance_double(Whatsapp::ChannelCreationService)
      allow(Whatsapp::ChannelCreationService).to receive(:new)
        .with(account, { waba_id: params[:waba_id], business_name: 'Test Business' }, phone_info, access_token)
        .and_return(channel_creation)
      allow(channel_creation).to receive(:perform).and_return(channel)

      allow(channel).to receive(:setup_webhooks)
      allow(channel).to receive(:phone_number).and_return('+1234567890')
      allow(channel).to receive_messages(id: 1, provider_config: {}, update_column: true)

      health_service = instance_double(Whatsapp::HealthService)
      allow(Whatsapp::HealthService).to receive(:new).and_return(health_service)
      allow(health_service).to receive(:fetch_health_status).and_return({
                                                                          platform_type: 'CLOUD_API',
                                                                          throughput: { 'level' => 'STANDARD' },
                                                                          messaging_limit_tier: 'TIER_1000'
                                                                        })
    end

    it 'creates channel and sets up webhooks' do
      expect(channel).to receive(:setup_webhooks)

      result = service.perform
      expect(result).to eq(channel)
    end

    context 'when gating the history sync flag' do
      it 'never constructs Whatsapp::HistorySyncService when the flag is off' do
        # Reason: the gate must live at the call site, not just inside the service, so flag OFF
        # means zero new code executes in the onboarding flow.
        expect(Whatsapp::HistorySyncService).not_to receive(:new)
        service.perform
      end

      it 'triggers Whatsapp::HistorySyncService when the flag is on' do
        history_sync_service = instance_double(Whatsapp::HistorySyncService, perform: nil)
        expect(Whatsapp::HistorySyncService).to receive(:new).with(channel).and_return(history_sync_service)

        with_modified_env WHATSAPP_HISTORY_SYNC_ENABLED: 'true' do
          service.perform
        end
      end
    end

    it 'checks health status after channel creation' do
      health_service = instance_double(Whatsapp::HealthService)
      allow(Whatsapp::HealthService).to receive(:new).and_return(health_service)
      expect(health_service).to receive(:fetch_health_status)

      service.perform
    end

    context 'when channel is in pending state' do
      it 'prompts reauthorization for pending channel' do
        health_service = instance_double(Whatsapp::HealthService)
        allow(Whatsapp::HealthService).to receive(:new).and_return(health_service)
        allow(health_service).to receive(:fetch_health_status).and_return({
                                                                            platform_type: 'NOT_APPLICABLE',
                                                                            throughput: { 'level' => 'STANDARD' },
                                                                            messaging_limit_tier: 'TIER_1000'
                                                                          })

        expect(channel).to receive(:prompt_reauthorization!)
        service.perform
      end

      it 'prompts reauthorization when throughput level is NOT_APPLICABLE' do
        health_service = instance_double(Whatsapp::HealthService)
        allow(Whatsapp::HealthService).to receive(:new).and_return(health_service)
        allow(health_service).to receive(:fetch_health_status).and_return({
                                                                            platform_type: 'CLOUD_API',
                                                                            throughput: { 'level' => 'NOT_APPLICABLE' },
                                                                            messaging_limit_tier: 'TIER_1000'
                                                                          })

        expect(channel).to receive(:prompt_reauthorization!)
        service.perform
      end
    end

    context 'when channel is healthy' do
      it 'does not prompt reauthorization for healthy channel' do
        expect(channel).not_to receive(:prompt_reauthorization!)
        service.perform
      end
    end

    context 'when parameters are invalid' do
      it 'raises ArgumentError for missing parameters' do
        invalid_service = described_class.new(account: account, params: { code: '', waba_id: '' })
        expect { invalid_service.perform }.to raise_error(ArgumentError, 'Required parameters are missing: code, waba_id')
      end

      it 'does not require business_id' do
        coexistence_service = described_class.new(account: account, params: params.except(:business_id))
        expect { coexistence_service.perform }.not_to raise_error
      end
    end

    context 'when service fails' do
      it 'logs and re-raises errors' do
        token_exchange = instance_double(Whatsapp::TokenExchangeService)
        allow(Whatsapp::TokenExchangeService).to receive(:new).and_return(token_exchange)
        allow(token_exchange).to receive(:perform).and_raise('Token error')

        expect(Rails.logger).to receive(:error).with('[WHATSAPP] Embedded signup failed: Token error')
        expect { service.perform }.to raise_error('Token error')
      end

      it 'prompts reauthorization when webhook setup fails' do
        # Create a real channel to test the actual webhook failure behavior
        real_channel = create(:channel_whatsapp, account: account, phone_number: '+1234567890',
                                                 validate_provider_config: false, sync_templates: false)

        # Mock the channel creation to return our real channel
        channel_creation = instance_double(Whatsapp::ChannelCreationService)
        allow(Whatsapp::ChannelCreationService).to receive(:new).and_return(channel_creation)
        allow(channel_creation).to receive(:perform).and_return(real_channel)

        # Mock webhook setup to fail
        allow(real_channel).to receive(:perform_webhook_setup).and_raise('Webhook setup error')

        # Verify channel is not marked for reauthorization initially
        expect(real_channel.reauthorization_required?).to be false

        # The service completes successfully even if webhook fails (webhook error is rescued in setup_webhooks)
        result = service.perform
        expect(result).to eq(real_channel)

        # Verify the channel is now marked for reauthorization
        expect(real_channel.reauthorization_required?).to be true
      end
    end

    context 'when recording how Meta finished the signup (#1315)' do
      let(:real_channel) do
        create(:channel_whatsapp, account: account, phone_number: '+1234567890',
                                  provider_config: { 'source' => 'embedded_signup', 'api_key' => 'stored-token' },
                                  validate_provider_config: false, sync_templates: false)
      end
      let(:trace_params) do
        params.merge(signup_event: 'FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING', signup_version: '3', is_coexistence: 'true')
      end

      before do
        channel_creation = instance_double(Whatsapp::ChannelCreationService, perform: real_channel)
        allow(Whatsapp::ChannelCreationService).to receive(:new).and_return(channel_creation)
        allow(real_channel).to receive(:setup_webhooks)
      end

      it 'keeps the event, version and coexistence on the channel without dropping its credentials' do
        # Reason: the container log is lost on each blue-green deploy; the channel is the durable proof.
        described_class.new(account: account, params: trace_params).perform

        config = real_channel.reload.provider_config
        expect(config).to include('source' => 'embedded_signup', 'signup_event' => 'FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING',
                                  'signup_version' => '3', 'signup_is_coexistence' => true)
        expect(config['signup_completed_at']).to be_present
        expect(config['api_key']).to eq('stored-token')
      end

      it 'does not re-run the remote credential check to store the trace' do
        # Reason: a save would call validate_provider_config, i.e. two Graph API requests per signup.
        expect(real_channel).not_to receive(:save!)
        expect(real_channel).not_to receive(:save)

        described_class.new(account: account, params: trace_params).perform
      end

      it 'logs one success line with the trace and no credentials' do
        allow(Rails.logger).to receive(:info)

        described_class.new(account: account, params: trace_params).perform

        expect(Rails.logger).to have_received(:info).with(
          "[WHATSAPP] Embedded signup completed account_id=#{account.id} channel_id=#{real_channel.id} " \
          'reauthorization=false event=FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING version=3 coexistence=true'
        )
      end

      it 'records an unknown trace when an older client sends no event' do
        allow(Rails.logger).to receive(:info)

        described_class.new(account: account, params: params).perform

        expect(real_channel.reload.provider_config).to include('signup_event' => '', 'signup_version' => '', 'signup_is_coexistence' => nil)
        expect(Rails.logger).to have_received(:info).with(a_string_including('event=none version=none coexistence=nil'))
      end

      it 'still connects the number and logs the error when the trace cannot be stored' do
        # Reason: the trace is evidence; a failed write must not reach the rescue that fails the signup.
        allow(real_channel).to receive(:update_column).and_raise(ActiveRecord::StatementInvalid, 'db down')
        allow(Rails.logger).to receive(:error)

        result = described_class.new(account: account, params: trace_params).perform

        expect(result).to eq(real_channel)
        expect(real_channel).to have_received(:setup_webhooks)
        expect(Rails.logger).to have_received(:error).with(
          "[WHATSAPP] Embedded signup trace not recorded channel_id=#{real_channel.id} error_class=ActiveRecord::StatementInvalid"
        )
        expect(Rails.logger).not_to have_received(:error).with(a_string_including('Embedded signup failed'))
      end

      it 'keeps the history sync request that runs after the trace is stored' do
        # Reason: HistorySyncService mutates provider_config in place and saves; it must not lose either write.
        client = instance_double(Whatsapp::FacebookApiClient, start_smb_app_data_sync: { 'request_id' => 'req-1' })
        allow(Whatsapp::FacebookApiClient).to receive(:new).and_return(client)

        with_modified_env WHATSAPP_HISTORY_SYNC_ENABLED: 'true' do
          described_class.new(account: account, params: trace_params).perform
        end

        config = real_channel.reload.provider_config
        expect(config).to include('signup_event' => 'FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING',
                                  'history_sync_request_ids' => { 'smb_app_state_sync' => 'req-1', 'history' => 'req-1' })
        expect(config['history_sync_requested_at']).to be_present
      end

      it 'strips characters that could forge a log line from client-sent values' do
        allow(Rails.logger).to receive(:info)
        forged = params.merge(signup_event: "FINISH\n[WHATSAPP] fake=1 #{'A' * 100}", signup_version: '3; drop')

        described_class.new(account: account, params: forged).perform

        config = real_channel.reload.provider_config
        expect(config['signup_event']).to eq("FINISHWHATSAPPfake1#{'A' * 45}")
        expect(config['signup_version']).to eq('3drop')
      end
    end

    context 'with reauthorization flow' do
      let(:inbox_id) { 123 }
      let(:reauth_service) { instance_double(Whatsapp::ReauthorizationService) }
      let(:service_with_inbox) do
        described_class.new(account: account, params: params, inbox_id: inbox_id)
      end

      before do
        allow(Whatsapp::ReauthorizationService).to receive(:new).with(
          account: account,
          inbox_id: inbox_id,
          phone_number_id: params[:phone_number_id],
          waba_id: params[:waba_id]
        ).and_return(reauth_service)
        allow(reauth_service).to receive(:perform).with(access_token, phone_info).and_return(channel)

        allow(channel).to receive(:phone_number).and_return('+1234567890')

        health_service = instance_double(Whatsapp::HealthService)
        allow(Whatsapp::HealthService).to receive(:new).and_return(health_service)
        allow(health_service).to receive(:fetch_health_status).and_return({
                                                                            platform_type: 'CLOUD_API',
                                                                            throughput: { 'level' => 'STANDARD' },
                                                                            messaging_limit_tier: 'TIER_1000'
                                                                          })
      end

      it 'uses ReauthorizationService and sets up webhooks' do
        expect(reauth_service).to receive(:perform)
        expect(channel).to receive(:setup_webhooks)

        result = service_with_inbox.perform
        expect(result).to eq(channel)
      end

      context 'with real channel requiring reauthorization' do
        let(:inbox) { create(:inbox, account: account) }
        let(:whatsapp_channel) do
          create(:channel_whatsapp, account: account, phone_number: '+1234567890',
                                    validate_provider_config: false, sync_templates: false)
        end
        let(:service_with_real_inbox) { described_class.new(account: account, params: params, inbox_id: inbox.id) }

        before do
          inbox.update!(channel: whatsapp_channel)
          whatsapp_channel.prompt_reauthorization!

          setup_reauthorization_mocks
          setup_health_service_mock
        end

        it 'records the trace of the reauthorization that just happened (#1315)' do
          allow(Rails.logger).to receive(:info)
          traced = described_class.new(account: account, params: params.merge(signup_event: 'FINISH', signup_version: '3'), inbox_id: inbox.id)

          traced.perform

          expect(whatsapp_channel.reload.provider_config).to include('signup_event' => 'FINISH', 'signup_version' => '3')
          expect(Rails.logger).to have_received(:info).with(a_string_including('reauthorization=true event=FINISH version=3'))
        end

        it 'clears reauthorization flag when reauthorization completes' do
          expect(whatsapp_channel.reauthorization_required?).to be true
          result = service_with_real_inbox.perform
          expect(result).to eq(whatsapp_channel)
          expect(whatsapp_channel.reauthorization_required?).to be false
        end

        private

        def setup_reauthorization_mocks
          reauth_service = instance_double(Whatsapp::ReauthorizationService)
          allow(Whatsapp::ReauthorizationService).to receive(:new).with(
            account: account,
            inbox_id: inbox.id,
            phone_number_id: params[:phone_number_id],
            waba_id: params[:waba_id]
          ).and_return(reauth_service)

          allow(reauth_service).to receive(:perform) do
            whatsapp_channel.reauthorized!
            whatsapp_channel
          end

          allow(whatsapp_channel).to receive(:setup_webhooks).and_return(true)
        end

        def setup_health_service_mock
          health_service = instance_double(Whatsapp::HealthService)
          allow(Whatsapp::HealthService).to receive(:new).and_return(health_service)
          allow(health_service).to receive(:fetch_health_status).and_return({
                                                                              platform_type: 'CLOUD_API',
                                                                              throughput: { 'level' => 'STANDARD' },
                                                                              messaging_limit_tier: 'TIER_1000'
                                                                            })
        end
      end
    end
  end
end
