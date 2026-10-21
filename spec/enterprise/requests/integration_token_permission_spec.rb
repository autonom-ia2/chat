require 'rails_helper'

# #2027 (lote 11 do épico #1784): integration_manage conecta integrações, webhooks e robôs e troca a credencial de uma
# caixa que já existe; token_manage vê e troca os segredos que a plataforma gera, sem emitir token acima da própria
# função. Credencial colada de outro sistema só volta para o administrador. Fica em spec/enterprise: a metade de função
# personalizada do permission_granted? é EE.
RSpec.describe 'Integration and token permissions (#2027)', :aggregate_failures, type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:plain_agent) { create(:user, account: account, role: :agent) }

  def member_with(permissions)
    user = create(:user, account: account, role: :agent)
    user.account_users.find_by(account: account).update!(custom_role: create(:custom_role, account: account, permissions: permissions))
    user
  end

  def headers_for(user)
    user.create_new_auth_token
  end

  describe 'webhooks' do
    let!(:webhook) { create(:webhook, account_id: account.id, inbox_id: nil) }
    let(:path) { "/api/v1/accounts/#{account.id}/webhooks" }

    it 'lets integration_manage manage webhooks without seeing the signing secret' do
      headers = headers_for(member_with(%w[integration_manage]))

      get path, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(webhook.secret)

      post path, params: { webhook: { url: 'https://example.com/hook', subscriptions: ['message_created'] } }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('payload', 'webhook')).not_to have_key('secret')
    end

    it 'shows the signing secret when token_manage comes along' do
      get path, headers: headers_for(member_with(%w[integration_manage token_manage])), as: :json

      expect(response.body).to include(webhook.secret)
    end

    it 'keeps token_manage alone and plain agents out' do
      get path, headers: headers_for(member_with(%w[token_manage])), as: :json
      expect(response).to have_http_status(:unauthorized)

      get path, headers: headers_for(plain_agent), as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'agent bots' do
    let!(:bot) { create(:agent_bot, account: account) }
    let(:path) { "/api/v1/accounts/#{account.id}/agent_bots" }

    it 'lets integration_manage create a bot but not rotate its token' do
      headers = headers_for(member_with(%w[integration_manage]))

      post path, params: { name: 'Robô', outgoing_url: 'https://example.com/bot' }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).not_to have_key('access_token')

      post "#{path}/#{bot.id}/reset_access_token", headers: headers, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'lets token_manage rotate the token and see it, without editing the bot' do
      headers = headers_for(member_with(%w[token_manage]))
      before_token = bot.access_token.token

      post "#{path}/#{bot.id}/reset_access_token", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['access_token']).to be_present
      expect(bot.reload.access_token.token).not_to eq(before_token)

      patch "#{path}/#{bot.id}", params: { outgoing_url: 'https://example.com/other' }, headers: headers, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'integration hooks' do
    it 'lets integration_manage connect an integration and plain agents not' do
      params = { hook: { app_id: 'webhook', settings: { url: 'https://example.com' } } }

      post "/api/v1/accounts/#{account.id}/integrations/hooks", params: params, headers: headers_for(plain_agent), as: :json
      expect(response).to have_http_status(:unauthorized)

      integrator = headers_for(member_with(%w[integration_manage]))
      post "/api/v1/accounts/#{account.id}/integrations/hooks", params: params, headers: integrator, as: :json
      expect(response).not_to have_http_status(:unauthorized)
    end
  end

  describe 'inbox secrets and credentials' do
    let(:api_inbox) { create(:inbox, account: account, channel: create(:channel_api, account: account)) }

    # The inbox secrets live in the inbox settings, which need at least inbox_view (or being a member).
    it 'lets token_manage rotate the HMAC token and receive it' do
      post "/api/v1/accounts/#{account.id}/inboxes/#{api_inbox.id}/rotate_hmac_token",
           headers: headers_for(member_with(%w[token_manage inbox_view])), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['hmac_token']).to eq(api_inbox.channel.reload.hmac_token)
    end

    it 'keeps inbox_manage from rotating secrets' do
      post "/api/v1/accounts/#{account.id}/inboxes/#{api_inbox.id}/reset_secret",
           headers: headers_for(member_with(%w[inbox_manage])), as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'lets inbox_manage rename the inbox but not point its webhook elsewhere' do
      headers = headers_for(member_with(%w[inbox_manage]))
      path = "/api/v1/accounts/#{account.id}/inboxes/#{api_inbox.id}"

      patch path, params: { name: 'Novo nome', channel: { webhook_url: api_inbox.channel.webhook_url } }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(api_inbox.reload.name).to eq('Novo nome')

      patch path, params: { channel: { webhook_url: 'https://example.com/elsewhere' } }, headers: headers, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(api_inbox.channel.reload.webhook_url).not_to eq('https://example.com/elsewhere')

      patch path, params: { channel: { webhook_url: 'https://example.com/elsewhere' } },
                  headers: headers_for(member_with(%w[inbox_manage integration_manage])), as: :json
      expect(response).to have_http_status(:ok)
      expect(api_inbox.channel.reload.webhook_url).to eq('https://example.com/elsewhere')
    end

    it 'keeps the stored mail password when a blank one comes back and never shows it to key holders' do
      email_inbox = create(:inbox, account: account, channel: create(:channel_email, account: account, imap_password: 'guardada'))
      headers = headers_for(member_with(%w[inbox_manage integration_manage]))

      patch "/api/v1/accounts/#{account.id}/inboxes/#{email_inbox.id}",
            params: { channel: { imap_password: '' } }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(email_inbox.channel.reload.imap_password).to eq('guardada')
      expect(response.body).not_to include('guardada')
    end

    it 'asks for the password again before pointing the mailbox to another server' do
      email_inbox = create(:inbox, account: account, channel: create(:channel_email, account: account, imap_enabled: true,
                                                                                     imap_address: 'imap.loja.test', imap_password: 'guardada'))
      path = "/api/v1/accounts/#{account.id}/inboxes/#{email_inbox.id}"
      headers = headers_for(member_with(%w[inbox_view integration_manage]))
      allow(Net::IMAP).to receive(:new)

      patch path, params: { channel: { imap_enabled: true, imap_address: 'imap.outro.test', imap_password: '' } }, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(email_inbox.channel.reload.imap_address).to eq('imap.loja.test')
      expect(Net::IMAP).not_to have_received(:new)
    end

    it 'lets integration_manage alone change how the mailbox connects, and nothing else' do
      email_inbox = create(:inbox, account: account, name: 'Contato',
                                   channel: create(:channel_email, account: account, imap_address: 'imap.loja.test', imap_password: 'guardada'))
      path = "/api/v1/accounts/#{account.id}/inboxes/#{email_inbox.id}"
      headers = headers_for(member_with(%w[inbox_view integration_manage]))

      patch path, params: { name: 'Contato', channel: { imap_address: 'imap.outro.test', imap_password: 'nova' } }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(email_inbox.channel.reload.imap_address).to eq('imap.outro.test')

      patch path, params: { name: 'Outro nome' }, headers: headers, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(email_inbox.reload.name).to eq('Contato')
    end

    it 'does not ask for the password when the mail form only sends back unset switches' do
      email_inbox = create(:inbox, account: account, channel: create(:channel_email, account: account, imap_address: 'imap.loja.test',
                                                                                     imap_password: 'guardada', imap_enable_ssl: nil))

      patch "/api/v1/accounts/#{account.id}/inboxes/#{email_inbox.id}",
            params: { channel: { imap_address: 'imap.loja.test', imap_enable_ssl: false, imap_password: '' } },
            headers: headers_for(member_with(%w[inbox_view integration_manage])), as: :json

      expect(response).to have_http_status(:ok)
      expect(email_inbox.channel.reload.imap_password).to eq('guardada')
    end

    it 'keeps integration_manage alone out of the other inbox settings' do
      headers = headers_for(member_with(%w[inbox_view integration_manage]))
      path = "/api/v1/accounts/#{account.id}/inboxes/#{api_inbox.id}"

      patch path, params: { working_hours: [{ day_of_week: 1, closed_all_day: true }] }, headers: headers, as: :json
      expect(response).to have_http_status(:unauthorized)

      patch path, params: { csat_survey_enabled: !api_inbox.csat_survey_enabled }, headers: headers, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'keeps inbox_manage from switching the mail server off' do
      email_inbox = create(:inbox, account: account, channel: create(:channel_email, account: account, imap_enabled: true))

      patch "/api/v1/accounts/#{account.id}/inboxes/#{email_inbox.id}",
            params: { channel: { imap_enabled: false } }, headers: headers_for(member_with(%w[inbox_manage])), as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(email_inbox.channel.reload.imap_enabled).to be(true)
    end

    it 'keeps inbox_manage from turning off the mail encryption' do
      email_inbox = create(:inbox, account: account, channel: create(:channel_email, account: account, smtp_enable_ssl_tls: true))

      patch "/api/v1/accounts/#{account.id}/inboxes/#{email_inbox.id}",
            params: { channel: { smtp_enable_ssl_tls: false } }, headers: headers_for(member_with(%w[inbox_manage])), as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(email_inbox.channel.reload.smtp_enable_ssl_tls).to be(true)
    end

    it 'does not save a mail server that fails the check' do
      email_inbox = create(:inbox, account: account, channel: create(:channel_email, account: account, imap_enabled: true,
                                                                                     imap_address: 'imap.loja.test', imap_password: 'guardada'))
      allow(Net::IMAP).to receive(:new).and_raise(SocketError)

      patch "/api/v1/accounts/#{account.id}/inboxes/#{email_inbox.id}",
            params: { name: 'Novo nome', channel: { imap_enabled: true, imap_address: 'imap.outro.test', imap_password: 'nova' } },
            headers: headers_for(admin), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(email_inbox.channel.reload.imap_address).to eq('imap.loja.test')
      expect(email_inbox.reload.name).not_to eq('Novo nome')
    end

    it 'shows how the mailbox connects to integration_manage, without the password, and the disconnection to everyone' do
      email_inbox = create(:inbox, account: account, channel: create(:channel_email, account: account, imap_address: 'imap.loja.test',
                                                                                     imap_password: 'guardada', imap_enabled: true))
      path = "/api/v1/accounts/#{account.id}/inboxes/#{email_inbox.id}"

      get path, headers: headers_for(member_with(%w[inbox_view integration_manage])), as: :json
      expect(response.parsed_body).to include('imap_address' => 'imap.loja.test', 'imap_enabled' => true)
      expect(response.parsed_body).not_to have_key('imap_password')

      get path, headers: headers_for(member_with(%w[inbox_manage])), as: :json
      expect(response.parsed_body).not_to have_key('imap_address')

      get path, headers: headers_for(admin), as: :json
      expect(response.parsed_body['imap_password']).to eq('guardada')
    end

    it 'leaves reconnecting a live WhatsApp inbox to integration_manage' do
      whatsapp_inbox = create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false).inbox
      params = { code: 'code', business_id: 'business', waba_id: 'waba', inbox_id: whatsapp_inbox.id }

      inbox_manager = headers_for(member_with(%w[inbox_manage]))
      post "/api/v1/accounts/#{account.id}/whatsapp/authorization", params: params, headers: inbox_manager, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'CRM integration tokens' do
    around do |example|
      with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run }
    end

    let(:path) { "/api/v1/accounts/#{account.id}/crm/integration_tokens" }

    it 'moves the tokens screen from crm_admin to token_manage' do
      get path, headers: headers_for(member_with(%w[crm_admin])), as: :json
      expect(response).to have_http_status(:unauthorized)

      get path, headers: headers_for(member_with(%w[token_manage])), as: :json
      expect(response).to have_http_status(:ok)
    end

    it 'leaves the Google conversions link to token_manage' do
      path = "/api/v1/accounts/#{account.id}/crm/google_conversion_feed"

      post path, headers: headers_for(member_with(%w[integration_manage crm_admin])), as: :json
      expect(response).to have_http_status(:unauthorized)

      post path, headers: headers_for(member_with(%w[token_manage crm_view])), as: :json
      expect(response).to have_http_status(:created)
    end

    it 'never mints a token above what the person holds' do
      headers = headers_for(member_with(%w[token_manage crm_view]))

      post path, params: { integration_token: { name: 'n8n', scopes: %w[crm_admin] } }, headers: headers, as: :json
      expect(response).to have_http_status(:unauthorized)

      post path, params: { integration_token: { name: 'n8n', scopes: %w[crm_view] } }, headers: headers, as: :json
      expect(response).to have_http_status(:created)
    end

    it 'never rotates a token above what the person holds' do
      post path, params: { integration_token: { name: 'n8n', scopes: %w[crm_admin] } }, headers: headers_for(admin), as: :json
      token_id = response.parsed_body['id'] || response.parsed_body.dig('payload', 'id')

      post "#{path}/#{token_id}/rotate", headers: headers_for(member_with(%w[token_manage crm_view])), as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'delegation' do
    it 'keeps both keys with administrators even for who builds roles' do
      builder = member_with(%w[custom_role_manage integration_manage token_manage])

      post "/api/v1/accounts/#{account.id}/custom_roles",
           params: { name: 'Integra', permissions: %w[integration_manage] }, headers: headers_for(builder), as: :json

      expect(response).not_to have_http_status(:ok)
      expect(account.custom_roles.where(name: 'Integra')).to be_empty
    end
  end
end
