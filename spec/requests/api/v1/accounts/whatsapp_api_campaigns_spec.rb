require 'rails_helper'

RSpec.describe 'WhatsApp API campaigns API', type: :request do
  around do |example|
    previous_value = ENV.fetch('WHATSAPP_API_CAMPAIGNS_ENABLED', nil)
    ENV['WHATSAPP_API_CAMPAIGNS_ENABLED'] = 'true'
    example.run
  ensure
    if previous_value.nil?
      ENV.delete('WHATSAPP_API_CAMPAIGNS_ENABLED')
    else
      ENV['WHATSAPP_API_CAMPAIGNS_ENABLED'] = previous_value
    end
  end

  it 'marks API inboxes explicitly for WhatsApp API campaigns' do
    account, user = create_account_and_user
    inbox = create_whatsapp_api_inbox(account: account, enabled: false)

    post "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/enable_whatsapp_api_campaigns",
         headers: auth_headers(user)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['additional_attributes']['campaign_channel_type']).to eq('whatsapp_api')
    expect(inbox.reload.channel.whatsapp_api_campaign_channel?).to be(true)
  end

  it 'creates a scheduled campaign without resolving or sending recipients immediately' do
    account, user, inbox, label = create_account_user_inbox_and_label
    create_labelled_contact(account: account, label: label, name: 'Ana Silva', phone_number: '+5511987654321')

    post "/api/v1/accounts/#{account.id}/whatsapp_api_campaigns",
         params: {
           title: 'Campanha API',
           inbox_id: inbox.id,
           message_body: 'Olá {{contact.first_name}}',
           scheduled_at: 10.minutes.from_now.iso8601,
           audience: [{ type: 'Label', id: label.id }]
         },
         headers: auth_headers(user)

    expect(response).to have_http_status(:created)
    payload = response.parsed_body['payload']
    expect(payload['status']).to eq('scheduled')
    expect(payload['message_body']).to eq('Olá {{contact.first_name}}')
    expect(WhatsappApiCampaign.last.whatsapp_api_campaign_recipients.count).to eq(0)
    expect(Message.where(account_id: account.id).count).to eq(0)
  end

  it 'stores text templates per enabled API inbox and rejects unsupported variables' do
    account, user = create_account_and_user
    first_inbox = create_whatsapp_api_inbox(account: account, name: 'WAHA 1')
    second_inbox = create_whatsapp_api_inbox(account: account, name: 'WAHA 2')

    post "/api/v1/accounts/#{account.id}/inboxes/#{first_inbox.id}/whatsapp_api_message_templates",
         params: {
           template: {
             name: 'Boas vindas',
             body: 'Olá {{contact.first_name}}'
           }
         },
         headers: auth_headers(user)

    expect(response).to have_http_status(:created)
    expect(response.parsed_body['payload']['variables']).to eq(['contact.first_name'])

    get "/api/v1/accounts/#{account.id}/inboxes/#{second_inbox.id}/whatsapp_api_message_templates",
        headers: auth_headers(user)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['payload']).to eq([])

    post "/api/v1/accounts/#{account.id}/inboxes/#{first_inbox.id}/whatsapp_api_message_templates",
         params: {
           template: {
             name: 'Com email',
             body: 'Olá {{contact.email}}'
           }
         },
         headers: auth_headers(user)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(first_inbox.whatsapp_api_message_templates.count).to eq(1)
  end

  it 'supports pause, resume and cancel lifecycle actions' do
    account, user, inbox, label = create_account_user_inbox_and_label
    create_labelled_contact(account: account, label: label, name: 'Ana Silva', phone_number: '+5511987654321')
    campaign = create_whatsapp_api_campaign(account: account, user: user, inbox: inbox, label: label)
    WhatsappApiCampaigns::AudienceResolver.new(campaign).perform
    campaign.update!(status: :running)

    post "/api/v1/accounts/#{account.id}/whatsapp_api_campaigns/#{campaign.id}/pause",
         headers: auth_headers(user)

    expect(response).to have_http_status(:ok)
    expect(campaign.reload).to be_paused

    post "/api/v1/accounts/#{account.id}/whatsapp_api_campaigns/#{campaign.id}/resume",
         headers: auth_headers(user)

    expect(response).to have_http_status(:ok)
    expect(campaign.reload).to be_running

    post "/api/v1/accounts/#{account.id}/whatsapp_api_campaigns/#{campaign.id}/cancel",
         headers: auth_headers(user)

    expect(response).to have_http_status(:ok)
    expect(campaign.reload).to be_cancelled
    expect(campaign.whatsapp_api_campaign_recipients.first.reload).to be_cancelled
  end

  it 'cancels recipients that are already marked as sending' do
    account, user, inbox, label = create_account_user_inbox_and_label
    create_labelled_contact(account: account, label: label, name: 'Ana Silva', phone_number: '+5511987654321')
    campaign = create_whatsapp_api_campaign(account: account, user: user, inbox: inbox, label: label)
    WhatsappApiCampaigns::AudienceResolver.new(campaign).perform
    campaign.whatsapp_api_campaign_recipients.first.update!(status: :sending, attempts: 1)
    campaign.update!(status: :running)

    post "/api/v1/accounts/#{account.id}/whatsapp_api_campaigns/#{campaign.id}/cancel",
         headers: auth_headers(user)

    expect(response).to have_http_status(:ok)
    expect(campaign.reload).to be_cancelled
    expect(campaign.whatsapp_api_campaign_recipients.first.reload).to be_cancelled
  end

  it 'does not allow disabling WhatsApp API marking while campaigns are active for the inbox' do
    account, user, inbox, label = create_account_user_inbox_and_label
    create_whatsapp_api_campaign(account: account, user: user, inbox: inbox, label: label)

    delete "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/disable_whatsapp_api_campaigns",
           headers: auth_headers(user)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('whatsapp_api_campaigns.inbox_has_active_campaigns')
    expect(inbox.reload.channel).to be_whatsapp_api_campaign_channel
  end

  it 'blocks endpoints when the feature flag is disabled' do
    account, user = create_account_and_user
    ENV['WHATSAPP_API_CAMPAIGNS_ENABLED'] = 'false'

    get "/api/v1/accounts/#{account.id}/whatsapp_api_campaigns", headers: auth_headers(user)

    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body['error']).to eq('whatsapp_api_campaigns.disabled')
  end

  it 'schedules a naive local-time campaign in the account operational zone, not UTC' do
    with_modified_env DEFAULT_OPERATIONAL_TIMEZONE: nil do
      account, user, inbox, label = create_account_user_inbox_and_label
      account.update!(reporting_timezone: 'America/Sao_Paulo')
      create_labelled_contact(account: account, label: label, name: 'Ana Silva', phone_number: '+5511987654321')

      post "/api/v1/accounts/#{account.id}/whatsapp_api_campaigns",
           params: {
             title: 'Campanha API',
             inbox_id: inbox.id,
             message_body: 'Olá {{contact.first_name}}',
             scheduled_at: '2999-07-10 09:00',
             audience: [{ type: 'Label', id: label.id }]
           },
           headers: auth_headers(user)

      expect(response).to have_http_status(:created)
      # 09:00 in America/Sao_Paulo (UTC-3) is 12:00 UTC — the silent-UTC bug would store 09:00 UTC.
      expect(WhatsappApiCampaign.last.scheduled_at.utc.strftime('%Y-%m-%d %H:%M')).to eq('2999-07-10 12:00')
    end
  end

  it 'rejects a naive scheduled_at when no operational timezone is configured' do
    with_modified_env DEFAULT_OPERATIONAL_TIMEZONE: nil do
      account, user, inbox, label = create_account_user_inbox_and_label

      post "/api/v1/accounts/#{account.id}/whatsapp_api_campaigns",
           params: {
             title: 'Campanha API',
             inbox_id: inbox.id,
             message_body: 'Olá {{contact.first_name}}',
             scheduled_at: '2999-07-10 09:00',
             audience: [{ type: 'Label', id: label.id }]
           },
           headers: auth_headers(user)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('scheduled_at_naive_timezone')
      expect(WhatsappApiCampaign.count).to eq(0)
    end
  end

  def auth_headers(user)
    { 'api_access_token' => user.access_token.token }
  end
end
