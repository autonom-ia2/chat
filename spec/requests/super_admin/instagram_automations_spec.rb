require 'rails_helper'

RSpec.describe 'Super Admin Instagram automation', type: :request do
  let(:path) { '/super_admin/instagram_automation' }
  let(:super_admin) { create(:super_admin) }

  around { |example| with_modified_env('INSTAGRAM_TESTER_SESSION_SOURCE' => 'env') { example.run } }

  it 'requires Super Admin authentication on every action' do
    get path, as: :json
    expect(response).to have_http_status(:unauthorized)
    [path, "#{path}/health", "#{path}/reconnect"].each do |endpoint|
      post endpoint, params: {}, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  it 'denies an ordinary account administrator' do
    sign_in(create(:account_user, role: 'administrator').user, scope: :user)
    get path, as: :json
    expect(response).to have_http_status(:unauthorized)
    [path, "#{path}/health", "#{path}/reconnect"].each do |endpoint|
      post endpoint, params: {}, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  context 'with Super Admin authentication' do
    before { sign_in(super_admin, scope: :super_admin) }

    it 'returns only metadata and sanitized status without inserting configuration records' do
      expect(GlobalConfigService).not_to receive(:load)
      with_modified_env('INSTAGRAM_TESTER_SESSION_SOURCE' => 'env', 'INSTAGRAM_TESTER_APP_NAME' => 'Synthetic App') do
        expect { get path, as: :json }.not_to change(InstallationConfig, :count)
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.keys).to contain_exactly('metadata', 'status')
        expect(response.parsed_body['metadata'].keys).to match_array(Instagram::Automation::Metadata::KEYS)
        expect(response.parsed_body.dig('metadata', 'INSTAGRAM_TESTER_APP_NAME')).to eq('Synthetic App')
      end
    end

    it 'renders malformed HTML submissions as 422 without reflecting the submitted shape' do
      ['synthetic-secret-do-not-echo', ['synthetic-secret-do-not-echo'], nil,
       { INSTAGRAM_TESTER_APP_NAME: ['synthetic-secret-do-not-echo'] }].each do |invalid|
        expect { post path, params: { instagram_automation: invalid } }.not_to change(InstallationConfig, :count)
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.media_type).to eq('text/html')
        expect(response.body).not_to include('synthetic-secret-do-not-echo')
      end
    end

    it 'persists allowed metadata and returns sanitized JSON' do
      post path, params: { instagram_automation: { INSTAGRAM_META_DEVELOPER_APP_ID: '12345' } }, as: :json
      expect(response).to have_http_status(:ok)
      expect(InstallationConfig.find_by!(name: 'INSTAGRAM_META_DEVELOPER_APP_ID').value).to eq('12345')
      expect(response.parsed_body.dig('metadata', 'INSTAGRAM_META_DEVELOPER_APP_ID')).to eq('12345')
    end

    it 'redirects an HTML save with a localized success flash in both supported locales' do
      %i[en pt_BR].each do |locale|
        I18n.with_locale(locale) do
          post path, params: { instagram_automation: { INSTAGRAM_TESTER_APP_NAME: '' } }
          expect(response).to redirect_to(path)
          follow_redirect!
          expect(Nokogiri::HTML(response.body).at_css('.flashes').text).to include(I18n.t('super_admin.instagram_automation.saved'))
        end
      end
    end

    it 'renders invalid HTML as 422 with safe fields preserved and a fixed localized message' do
      create(:installation_config, name: 'INSTAGRAM_META_BUSINESS_ID', value: '10001')
      %i[en pt_BR].each do |locale|
        I18n.with_locale(locale) do
          expect do
            post path, params: { instagram_automation: {
              INSTAGRAM_META_DEVELOPER_APP_ID: '000123', INSTAGRAM_META_BUSINESS_ID: 'bad<script>alert(1)</script>',
              INSTAGRAM_TESTER_APP_NAME: 'Updated App', INSTAGRAM_TESTER_SESSION_JSON: 'synthetic-secret-do-not-echo'
            } }
          end.not_to change(InstallationConfig, :count)

          expect(response).to have_http_status(:unprocessable_entity)
          page = Nokogiri::HTML(response.body)
          expect(page.at_css('#instagram-automation [role="alert"]').text)
            .to include(I18n.t('super_admin.instagram_automation.invalid_configuration'))
          expect(page.at_css('input[name="instagram_automation[INSTAGRAM_META_DEVELOPER_APP_ID]"]')['value']).to eq('000123')
          expect(page.at_css('input[name="instagram_automation[INSTAGRAM_TESTER_APP_NAME]"]')['value']).to eq('Updated App')
          expect(page.at_css('input[name="instagram_automation[INSTAGRAM_META_BUSINESS_ID]"]')['value']).to eq('10001')
          expect(response.body).not_to include('bad<script>', 'synthetic-secret-do-not-echo')
        end
      end
    end

    it 'rejects unsupported fields, invalid shapes and malformed values without partial writes or echoing input' do
      [
        { INSTAGRAM_META_BUSINESS_ID: 'invalid' }, { INSTAGRAM_META_BUSINESS_ID: ['123'] },
        { INSTAGRAM_TESTER_APP_NAME: '  ' }, { INSTAGRAM_TESTER_SESSION_JSON: 'synthetic-secret' },
        { INSTAGRAM_TESTER_AUTOMATION_ENABLED: 'true' }, 'synthetic-secret', ['synthetic-secret'], nil
      ].each do |invalid|
        expect { post path, params: { instagram_automation: invalid }, as: :json }.not_to change(InstallationConfig, :count)
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body).to eq('error' => 'invalid_configuration')
      end
    end

    it 'recalculates health without saving metadata, invalidating sessions or making external calls' do
      expect(Instagram::Testers::SessionStore).not_to receive(:new)
      expect(Instagram::Testers::Client).not_to receive(:new)
      with_modified_env('INSTAGRAM_TESTER_SESSION_SOURCE' => 'env') do
        expect { post "#{path}/health", as: :json }
          .not_to change(InstallationConfig, :count)
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.dig('status', 'manager_connectivity')).to eq('unknown')
        expect(response.parsed_body.dig('status', 'checked_at')).to be_present
        expect(response.parsed_body.dig('status', 'meta_connectivity')).to eq('unknown')
      end
    end

    it 'redirects an HTML health check with an honest localized local-only flash' do
      post "#{path}/health"
      expect(response).to redirect_to(path)
      follow_redirect!
      expect(Nokogiri::HTML(response.body).at_css('.flashes').text).to include(I18n.t('super_admin.instagram_automation.health_checked'))
    end

    it 'keeps reconnect unavailable and never invalidates the current session' do
      expect(Instagram::Testers::SessionStore).not_to receive(:new)
      expect(Instagram::Testers::Client).not_to receive(:new)
      expect { post "#{path}/reconnect", as: :json }.not_to change(InstallationConfig, :count)
      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body).to eq('error' => 'operator_channel_unavailable')
      post "#{path}/reconnect"
      expect(response).to redirect_to(path)
      follow_redirect!
      expect(Nokogiri::HTML(response.body).at_css('.flashes').text)
        .to include(I18n.t('super_admin.instagram_automation.operator_channel_unavailable'))
    end

    it 'rejects unknown top-level params on every POST without enqueueing or echoing input' do
      expect(Instagram::Automation::OperatorControl).not_to receive(:new)
      [path, "#{path}/health", "#{path}/reconnect"].each do |endpoint|
        expect do
          post endpoint, params: { actor_id: 'synthetic-secret-do-not-echo', instagram_automation: { INSTAGRAM_TESTER_APP_NAME: 'App' } }, as: :json
        end.not_to change(InstallationConfig, :count)
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body).to eq('error' => 'invalid_configuration')
      end
    end

    it 'rejects configuration params on health/reconnect in HTML without a false success message' do
      ["#{path}/health", "#{path}/reconnect"].each do |endpoint|
        post endpoint, params: { instagram_automation: { INSTAGRAM_TESTER_SESSION_JSON: 'synthetic-secret-do-not-echo' } }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).not_to include('synthetic-secret-do-not-echo')
        expect(Nokogiri::HTML(response.body).at_css('#instagram-automation [role="alert"]')).to be_present
      end
    end

    it 'enqueues using the authenticated Super Admin actor and reports accepted, not renewed' do
      control = instance_double(Instagram::Automation::OperatorControl)
      queued = { 'id' => SecureRandom.uuid, 'action' => 'reconnect', 'state' => 'queued', 'actor_id' => super_admin.id.to_s,
                 'created_at' => Time.current.iso8601, 'updated_at' => Time.current.iso8601 }
      allow(Instagram::Automation::OperatorControl).to receive(:new).and_return(control)
      expect(control).to receive(:enqueue).with(actor_id: super_admin.id).and_return(queued)

      with_modified_env('INSTAGRAM_TESTER_SESSION_SOURCE' => 'managed') do
        post "#{path}/reconnect", as: :json
      end
      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body).to eq('request' => queued)
    end

    it 'redirects accepted HTML reconnection with a localized queued message' do
      control = instance_double(Instagram::Automation::OperatorControl)
      allow(Instagram::Automation::OperatorControl).to receive(:new).and_return(control)
      expect(control).to receive(:enqueue).with(actor_id: super_admin.id).twice.and_return('state' => 'queued')
      %i[en pt_BR].each do |locale|
        I18n.with_locale(locale) do
          with_modified_env('INSTAGRAM_TESTER_SESSION_SOURCE' => 'managed') { post "#{path}/reconnect" }
          expect(response).to redirect_to(path)
          follow_redirect!
          expect(Nokogiri::HTML(response.body).at_css('.flashes').text).to include(I18n.t('super_admin.instagram_automation.reconnect_queued'))
        end
      end
    end

    context 'with real request forgery protection' do
      around do |example|
        previous = SuperAdmin::InstagramAutomationsController.allow_forgery_protection
        SuperAdmin::InstagramAutomationsController.allow_forgery_protection = true
        example.run
      ensure
        SuperAdmin::InstagramAutomationsController.allow_forgery_protection = previous
      end

      it 'rejects absent/invalid CSRF on every POST through IntegrationSession without mutations' do
        session = ActionDispatch::Integration::Session.new(Rails.application)
        session.get(path)
        expect(session.response).to have_http_status(:ok)
        expect(Instagram::Automation::OperatorControl).not_to receive(:new)
        tokens = [nil, 'invalid-synthetic-csrf']
        [path, "#{path}/health", "#{path}/reconnect"].each do |endpoint|
          tokens.each do |token|
            expect do
              session.post(endpoint, params: { instagram_automation: { INSTAGRAM_TESTER_APP_NAME: 'Unsaved' } },
                                     headers: { 'ACCEPT' => 'application/json', 'X-CSRF-Token' => token })
            end.not_to change(InstallationConfig, :count)
            expect(session.response).to have_http_status(:unprocessable_entity)
            expect(session.response.parsed_body).to eq('error' => 'invalid_request')
          end
        end
      end

      it 'accepts a real session CSRF token for all three actions and binds the actor' do
        session = ActionDispatch::Integration::Session.new(Rails.application)
        session.get(path)
        token = Nokogiri::HTML(session.response.body).at_css('meta[name="csrf-token"]')['content']
        headers = { 'ACCEPT' => 'application/json', 'X-CSRF-Token' => token }
        session.post(path, params: { instagram_automation: { INSTAGRAM_TESTER_APP_NAME: 'Saved' } }, headers: headers)
        expect(session.response).to have_http_status(:ok)
        session.post("#{path}/health", headers: headers)
        expect(session.response).to have_http_status(:ok)

        control = instance_double(Instagram::Automation::OperatorControl)
        allow(Instagram::Automation::OperatorControl).to receive(:new).and_return(control)
        expect(control).to receive(:enqueue).with(actor_id: super_admin.id).and_return('state' => 'queued')
        with_modified_env('INSTAGRAM_TESTER_SESSION_SOURCE' => 'managed') do
          session.post("#{path}/reconnect", headers: headers)
        end
        expect(session.response).to have_http_status(:accepted)
      end

      it 'renders an HTML CSRF failure as a safe panel with 422' do
        session = ActionDispatch::Integration::Session.new(Rails.application)
        session.get(path)
        session.post(path, params: { instagram_automation: { INSTAGRAM_TESTER_SESSION_JSON: 'synthetic-secret-do-not-echo' } })

        expect(session.response).to have_http_status(:unprocessable_entity)
        expect(session.response.media_type).to eq('text/html')
        expect(session.response.body).not_to include('synthetic-secret-do-not-echo')
        expect(Nokogiri::HTML(session.response.body).at_css('#instagram-automation [role="alert"]').text)
          .to include(I18n.t('super_admin.instagram_automation.invalid_request'))
      end
    end
  end
end
