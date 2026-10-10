require 'rails_helper'

# chat#1217 — trocar a caixa de conta do WhatsApp sem gravar credencial de outro número.
describe Whatsapp::SwitchAccount::SameNumberGuard do
  let(:account) { create(:account) }
  let(:channel) do
    ch = build(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', phone_number: '+5511978622068',
                                  provider_config: { 'api_key' => 'old', 'phone_number_id' => 'old_phone', 'business_account_id' => 'old_waba' })
    allow(ch).to receive(:validate_provider_config).and_return(true)
    allow(ch).to receive(:sync_templates)
    allow(ch).to receive(:setup_webhooks)
    ch.save!
    ch
  end
  let!(:inbox) { create(:inbox, channel: channel, account: account) }
  let(:params) { { code: 'code', waba_id: 'new_waba', phone_number_id: 'new_phone' } }
  let(:phone_info) { { phone_number_id: 'new_phone', phone_number: '+5511978622068', business_name: 'GTA Assist' } }
  let(:service) { Whatsapp::EmbeddedSignupService.new(account: account, params: params, inbox_id: inbox.id) }

  before do
    allow(Whatsapp::TokenExchangeService).to receive(:new).and_return(instance_double(Whatsapp::TokenExchangeService, perform: 'new_token'))
    allow(Whatsapp::PhoneInfoService).to receive(:new)
      .and_return(instance_double(Whatsapp::PhoneInfoService, perform: phone_info))
  end

  it 'is prepended to the embedded signup service' do
    expect(Whatsapp::EmbeddedSignupService.ancestors).to include(described_class)
  end

  context 'when Meta returns another number' do
    let(:phone_info) { { phone_number_id: 'new_phone', phone_number: '+5511944547873', business_name: 'Outra' } }

    it 'raises a typed error and keeps the old credentials' do
      expect { service.perform }.to raise_error(Whatsapp::SwitchAccount::PhoneNumberMismatchError) do |error|
        expect(error.expected).to eq('+5511978622068')
        expect(error.received).to eq('+5511944547873')
      end

      expect(channel.reload.provider_config).to include('phone_number_id' => 'old_phone', 'business_account_id' => 'old_waba')
    end
  end

  context 'when Meta returns the same number in a new account' do
    let(:phone_info) { { phone_number_id: 'new_phone', phone_number: '+5511978622068', business_name: 'GTA Assist' } }

    it 'hands the same inbox to the Chatwoot reauthorization' do
      reauthorization = instance_double(Whatsapp::ReauthorizationService, perform: channel)
      allow(Whatsapp::ReauthorizationService).to receive(:new)
        .with(account: account, inbox_id: inbox.id, phone_number_id: 'new_phone', waba_id: 'new_waba').and_return(reauthorization)

      expect(service.perform).to eq(channel)
      expect(reauthorization).to have_received(:perform).with('new_token', phone_info)
    end

    it 'drops the old account templates and syncs the new ones' do
      allow(Whatsapp::ReauthorizationService).to receive(:new)
        .and_return(instance_double(Whatsapp::ReauthorizationService, perform: channel))

      expect { service.perform }.to have_enqueued_job(Channels::Whatsapp::TemplatesSyncJob).with(channel)
      expect(channel.reload.message_templates).to eq([])
    end

    it 'keeps the templates when the account did not change' do
      params[:waba_id] = 'old_waba'
      allow(Whatsapp::ReauthorizationService).to receive(:new)
        .and_return(instance_double(Whatsapp::ReauthorizationService, perform: channel))

      expect { service.perform }.not_to have_enqueued_job(Channels::Whatsapp::TemplatesSyncJob)
      expect(channel.reload.message_templates).not_to be_empty
    end
  end

  context 'when creating a new inbox' do
    let(:service) { Whatsapp::EmbeddedSignupService.new(account: account, params: params) }
    let(:phone_info) { { phone_number_id: 'new_phone', phone_number: '+5511944547873', business_name: 'Nova' } }

    it 'does not apply the guard' do
      creation = instance_double(Whatsapp::ChannelCreationService, perform: channel)
      allow(Whatsapp::ChannelCreationService).to receive(:new).and_return(creation)
      allow(Whatsapp::HealthService).to receive(:new).and_return(instance_double(Whatsapp::HealthService, fetch_health_status: nil))

      expect(service.perform).to eq(channel)
    end
  end
end
