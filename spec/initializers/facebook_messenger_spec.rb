require 'rails_helper'

describe 'Facebook Messenger webhook', type: :request do
  let(:verify_token) { 'test-fb-verify-token' }

  before do
    InstallationConfig.where(name: %w[FB_VERIFY_TOKEN FB_APP_SECRET]).delete_all
    GlobalConfig.clear_cache
  end

  describe 'GET /bot' do
    let(:challenge) { 'test-challenge' }

    def verify_with(params)
      get '/bot', params: { 'hub.mode' => 'subscribe', 'hub.challenge' => challenge }.merge(params)
    end

    it 'returns the challenge when the verify token matches' do
      with_modified_env FB_VERIFY_TOKEN: verify_token do
        verify_with('hub.verify_token' => verify_token)
      end

      expect(response.body).to eq(challenge)
    end

    it 'does not return the challenge when the verify token is wrong' do
      with_modified_env FB_VERIFY_TOKEN: verify_token do
        verify_with('hub.verify_token' => 'wrong-token')
      end

      expect(response.body).not_to include(challenge)
    end

    it 'does not return the challenge when the verify token is missing' do
      with_modified_env FB_VERIFY_TOKEN: verify_token do
        verify_with({})
      end

      expect(response.body).not_to include(challenge)
    end

    it 'does not return the challenge when no verify token is configured' do
      with_modified_env FB_VERIFY_TOKEN: '' do
        verify_with('hub.verify_token' => '')
      end

      expect(response.body).not_to include(challenge)
    end
  end

  # Fork (upgrade 4.20.1, #3120): POST /bot is served by the fork route `webhooks/facebook_page#events` (#2200), declared
  # before this mount in config/routes.rb, as on main. It checks X-Hub-Signature-256 against FB_APP_SECRET or
  # WHATSAPP_APP_SECRET and answers 401 when the signature is missing or wrong; its spec is
  # spec/controllers/webhooks/facebook_page_controller_spec.rb. Upstream's POST examples for this mount (#16576) never
  # reach it here, so they were removed; the mount still answers the GET verification above.
end
