require 'rails_helper'

# #2907: aviso `account_update` da Meta. Formato tirado da doc oficial (webhooks/reference/account_update).
RSpec.describe Whatsapp::AccessLoss::AccountUpdateJob do
  let(:waba_id) { '980198427658004' }
  let!(:channel) { waba_channel(waba_id) }
  let!(:other_channel) { waba_channel('111') }

  def waba_channel(waba)
    create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false).tap do |record|
      record.update_columns(provider_config: record.provider_config.merge('business_account_id' => waba)) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  after { [channel, other_channel].each(&:reauthorized!) }

  it 'PARTNER_REMOVED: acha a WABA em waba_info (o entry.id é do parceiro) e marca só as caixas dela' do
    described_class.perform_now([{ 'entry_id' => '2949482758682047',
                                   'value' => { 'event' => 'PARTNER_REMOVED', 'waba_info' => { 'waba_id' => waba_id },
                                                'disconnection_info' => { 'reason' => 'PRIMARY_INACTIVITY', 'initiated_by' => 'SYSTEM' } } }])

    expect(channel.reauthorization_required?).to be(true)
    expect(other_channel.reauthorization_required?).to be(false)
  end

  it 'ACCOUNT_OFFBOARDED, ACCOUNT_DELETED e PARTNER_APP_UNINSTALLED marcam; WABA no entry.id quando não há waba_info' do
    %w[ACCOUNT_OFFBOARDED ACCOUNT_DELETED PARTNER_APP_UNINSTALLED].each do |event|
      channel.reauthorized!
      described_class.perform_now([{ 'entry_id' => waba_id, 'value' => { 'event' => event } }])

      expect(channel.reauthorization_required?).to be(true), event
    end
  end

  it 'ACCOUNT_RECONNECTED apaga o aviso e pede a checagem de saúde (que marca de novo se o acesso não voltou)' do
    channel.prompt_reauthorization!
    allow(Channels::Whatsapp::HealthSyncJob).to receive(:perform_later)

    described_class.perform_now([{ 'entry_id' => waba_id, 'value' => { 'event' => 'ACCOUNT_RECONNECTED' } }])

    expect(Channels::Whatsapp::HealthSyncJob).to have_received(:perform_later).with(channel)
    expect(channel.reauthorization_required?).to be(false)
  end

  it 'eventos que não são de acesso (PARTNER_ADDED, VERIFIED_ACCOUNT) e WABA desconhecida não mexem em nada' do
    described_class.perform_now([{ 'entry_id' => waba_id, 'value' => { 'event' => 'PARTNER_ADDED' } },
                                 { 'entry_id' => waba_id, 'value' => { 'event' => 'VERIFIED_ACCOUNT' } },
                                 { 'entry_id' => '999', 'value' => { 'event' => 'ACCOUNT_DELETED' } }])

    expect(channel.reauthorization_required?).to be(false)
    expect(other_channel.reauthorization_required?).to be(false)
  end
end
