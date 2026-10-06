require 'rails_helper'

# #1004: the audience has its own SMS badge (channels.sms) with the phone count; born on only with
# an SMS inbox connected; PATCH .../channels turns it on/off; a pending SMS campaign holds it.
RSpec.describe 'Audience SMS badge (#1004)', :aggregate_failures, type: :request do
  around do |example|
    with_modified_env(CAMPAIGN_IMPORT_ENABLED: 'true') { example.run }
  end

  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  let(:content) { "Nome,Celular\nAna,11987654321\nBia,21987654321\n" }

  def audience
    @audience ||= saved_audience(account: account, user: user, content: content)
  end

  def patch_channels(body)
    headers = { 'api_access_token' => user.access_token.token }
    patch "/api/v1/accounts/#{account.id}/campaign_imports/#{audience.id}/channels", params: body, headers: headers, as: :json
  end

  def linked_sms_campaign(inbox)
    campaign = create(:campaign, account: account, inbox: inbox, title: 'Parcela outubro', audience: [], message: 'Oi')
    CampaignAudienceLink.create!(account: account, campaign: campaign, campaign_import: audience)
    campaign
  end

  it 'is born off ("sem caixa") without an SMS inbox, and cannot be turned on until one exists' do
    expect(audience.channels['sms']).to eq('enabled' => false, 'count' => 2)

    patch_channels({ sms: true })
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('campaign_import.channel_without_inbox')

    journey_twilio_sms_inbox(account)
    patch_channels({ sms: true })
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('payload', 'channels', 'sms')).to eq('enabled' => true, 'count' => 2)
  end

  it 'is born on with an SMS inbox (Bandwidth counts), and turns off and on' do
    journey_bandwidth_inbox(account)
    expect(audience.channels['sms']).to eq('enabled' => true, 'count' => 2)

    patch_channels({ sms: false })
    expect(audience.reload.channels['sms']).to eq('enabled' => false, 'count' => 2)
    expect(audience.channels.dig('whatsapp', 'enabled')).to be(true)
  end

  it 'does not count a Twilio WhatsApp inbox as SMS' do
    create(:channel_twilio_sms, :whatsapp, account: account)

    expect(audience.channels.dig('sms', 'enabled')).to be(false)
  end

  it 'gives an audience saved before #1004 an sms badge that can be turned on' do
    journey_twilio_sms_inbox(account)
    audience.update!(channels: audience.channels.except('sms'))

    patch_channels({ sms: true })

    expect(response).to have_http_status(:ok)
    expect(audience.reload.channels['sms']).to eq('enabled' => true, 'count' => 2)
  end

  it 'keeps the badge on while a pending SMS campaign uses it; WhatsApp is not held by it' do
    inbox = journey_twilio_sms_inbox(account)
    campaign = linked_sms_campaign(inbox)

    patch_channels({ sms: false })
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to include('code' => 'audience_in_use',
                                            'campaigns' => [{ 'title' => 'Parcela outubro', 'display_id' => campaign.display_id }])

    patch_channels({ whatsapp: false })
    expect(response).to have_http_status(:ok)

    campaign.update_columns(campaign_status: Campaign.campaign_statuses[:completed]) # rubocop:disable Rails/SkipsModelValidations
    patch_channels({ sms: false })
    expect(response).to have_http_status(:ok)
  end
end
