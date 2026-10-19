require 'rails_helper'

# chat#1709 (rodada 2): o recibo "ouvido" do áudio que mandamos, no PATCH de status do conector (`c2y_played_at`).
RSpec.describe 'WAHA played receipt', type: :request do
  let(:channel) do
    create(:channel_api, webhook_url: 'https://waha.example/webhooks/chatwoot/abc',
                         additional_attributes: { 'provider' => 'waha', 'session' => 's1' })
  end
  let(:account) { channel.account }
  let(:connector) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, inbox: channel.inbox, account: account) }
  let(:played_at) { '2026-10-16T12:00:00Z' }

  before do
    channel.update!(additional_attributes: channel.additional_attributes.merge('account_token_owner_user_id' => connector.id))
    create(:inbox_member, user: agent, inbox: channel.inbox)
  end

  def ours(file_type: :audio)
    message = conversation.messages.new(message_type: :outgoing, content: nil, inbox: channel.inbox, account: account, sender: connector)
    message.attachments.build(account_id: account.id, file_type: file_type,
                              file: { io: StringIO.new('x'), filename: 'a.ogg', content_type: 'audio/ogg' })
    message.save!
    message
  end

  def receipt(message, user: connector)
    patch "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/#{message.id}",
          params: { status: 'read', c2y_played_at: played_at }, headers: user.create_new_auth_token, as: :json
  end

  it 'records played_at once on our audio with the flag, from the connector only' do
    account.enable_features!(Waha::RichNative::FLAG)
    audio = ours

    receipt(audio, user: agent)
    expect(audio.reload.content_attributes).not_to have_key('played_at')

    receipt(audio)
    expect(response).to have_http_status(:success)
    expect(audio.reload.content_attributes['played_at']).to eq(Time.iso8601(played_at).iso8601)
    expect(audio.status).to eq('read')
  end

  it 'ignores the parameter without the flag, as main does' do
    audio = ours

    receipt(audio)

    expect(response).to have_http_status(:success)
    expect(audio.reload.content_attributes).not_to have_key('played_at')
    expect(audio.status).to eq('read')
  end
end
