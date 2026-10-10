require 'rails_helper'

# chat#1217 — a caixa mantém o nome escolhido pela operação ao reconectar ou trocar de conta.
describe Whatsapp::SwitchAccount::KeepInboxName do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
  end
  let(:inbox) { create(:inbox, account: account, channel: channel, name: '5511978622068') }
  let(:phone_info) { { phone_number: channel.phone_number, business_name: 'GTA Assist' } }

  before do
    stub_request(:get, %r{\Ahttps://graph\.facebook\.com/v14\.0/.+/message_templates\?access_token=new-token\z})
      .to_return(status: 200, body: { data: [] }.to_json, headers: { 'Content-Type' => 'application/json' })
    stub_request(:get, %r{\Ahttps://graph\.facebook\.com/v14\.0/.+/phone_numbers\?.*access_token=new-token})
      .to_return(status: 200, body: { data: [{ id: 'new-phone-id' }] }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  it 'keeps the inbox name while saving the new account' do
    Whatsapp::ReauthorizationService.new(account: account, inbox_id: inbox.id, phone_number_id: 'new-phone-id', waba_id: 'new-waba-id')
                                    .perform('new-token', phone_info)

    expect(inbox.reload.name).to eq('5511978622068')
    expect(channel.reload.provider_config).to include('phone_number_id' => 'new-phone-id', 'business_account_id' => 'new-waba-id')
  end
end
