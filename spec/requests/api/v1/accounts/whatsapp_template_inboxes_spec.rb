require 'rails_helper'

# As caixas que a tela de Modelos e a Nova campanha mostram (#1332): agrupadas pela conta do WhatsApp (WABA) sem
# mandar o id da WABA, com "precisa reconectar".
RSpec.describe 'WhatsApp template inboxes API (#1332)', type: :request do
  let(:account) { create(:account, name: 'Hub2you') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:path) { "/api/v1/accounts/#{account.id}/whatsapp_template_inboxes" }

  def cloud_channel(waba: '770011223344')
    channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
    channel.update_columns(provider_config: channel.provider_config.merge('business_account_id' => waba)) # rubocop:disable Rails/SkipsModelValidations
    channel
  end

  it 'groups the numbers of the same WhatsApp account under the first inbox' do
    first = cloud_channel
    second = cloud_channel
    create(:channel_whatsapp, account: account, provider: 'default', sync_templates: false, validate_provider_config: false)

    get path, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    rows = response.parsed_body['payload']
    expect(rows.pluck('id')).to eq([first.inbox.id, second.inbox.id])
    expect(rows).to all(include('group_id' => first.inbox.id, 'group_name' => 'Hub2you', 'reconnect' => false))
    expect(rows.first).to include('phone_number' => first.phone_number)
    expect(rows.first['template_sends']).to eq({})
    expect(response.body).not_to include('770011223344')
  end

  it 'names each group by its first inbox when there is more than one WhatsApp account' do
    first = cloud_channel
    other = cloud_channel(waba: '880099887766')
    key = other.send(:reauthorization_required_key)
    Redis::Alfred.set(key, true)

    get path, headers: admin.create_new_auth_token, as: :json
    Redis::Alfred.delete(key)

    rows = response.parsed_body['payload'].index_by { |row| row['id'] }
    expect(rows[first.inbox.id]).to include('group_id' => first.inbox.id, 'group_name' => first.inbox.name, 'reconnect' => false)
    expect(rows[other.inbox.id]).to include('group_id' => other.inbox.id, 'group_name' => other.inbox.name, 'reconnect' => true)
  end

  it 'never lists inboxes of another account' do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)

    get path, headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body['payload']).to eq([])
  end

  it 'refuses an agent without a role' do
    get path, headers: create(:user, account: account, role: :agent).create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
