require 'rails_helper'

RSpec.describe 'Super Admin Instagram automation UI', type: :request do
  let(:path) { '/super_admin/instagram_automation' }
  let(:status) do
    {
      global_gate: false, config_complete: false, session: { state: 'missing' },
      proxy: { configured: false, valid: false }, coordination: { configured: false },
      meta_creation_disabled: false, manager_connectivity: 'unknown', meta_connectivity: 'unknown',
      managed_session: true, manager: nil, control: nil, checked_at: nil
    }
  end
  let(:page) { Nokogiri::HTML(response.body) }
  let(:super_admin) { create(:super_admin) }

  before do
    sign_in(super_admin, scope: :super_admin)
    allow(Instagram::Automation::LocalStatus).to receive(:new).and_return(
      instance_double(Instagram::Automation::LocalStatus, call: status)
    )
  end

  it 'renders the dedicated page with five labeled metadata fields' do
    get path

    expect(response).to have_http_status(:ok)
    content = page.at_css('#instagram-automation')
    inputs = content.css('input[type="text"]')
    expect(inputs.map { |input| input['name'] }).to match_array(
      Instagram::Automation::Metadata::KEYS.map { |key| "instagram_automation[#{key}]" }
    )
    inputs.each do |input|
      expect(content.at_css("label[for='#{input['id']}']")).to be_present
      expect(content.at_css("##{input['aria-describedby']}")).to be_present
    end
    expect(content.text).to include('Meta Developer App ID', 'Instagram App ID', 'OAuth', 'RolesTable doc_id')
  end

  it 'uses server-side actions and accessible status rows without native selects, CSS or scripts' do
    get path

    content = page.at_css('#instagram-automation')
    expect(content.css('form').map { |form| form['action'] }).to contain_exactly(path, "#{path}/health", "#{path}/reconnect")
    expect(content.css('form').map { |form| form['method'] }).to all(eq('post'))
    expect(content.css('select, style, [style], script')).to be_empty
    expect(content.css('[data-component] h3').count).to eq(6)
    expect(content.text).to include(I18n.t('super_admin.instagram_automation.unknown_time'))
    expect(content.at_css("form[action='#{path}/reconnect'] button")['disabled']).to be_present
    expect(content.at_css("a[href='#{path}']").text).to eq(I18n.t('super_admin.instagram_automation.refresh'))
  end

  it 'posts browser access only for the actor who owns an active request' do
    status.merge!(operator_browser_configured: true,
                  control: { 'state' => 'running', 'actor_id' => super_admin.id,
                             'created_at' => Time.current.iso8601, 'updated_at' => Time.current.iso8601 })
    with_modified_env('INSTAGRAM_TESTER_SESSION_SOURCE' => 'managed') do
      get path
      form = page.at_css("form[action='#{path}/browser']")
      expect(form['method']).to eq('post')
      expect(form['target']).to eq('_blank')
      expect(form['rel']).to include('noopener')
      expect(form['rel']).not_to include('noreferrer')
      expect(form.at_css('button').text).to eq(I18n.t('super_admin.instagram_automation.open_remote_browser'))
      expect(page.at_css("a[href*='vnc']")).to be_nil
      status[:control]['actor_id'] = super_admin.id + 1
      get path
      expect(Nokogiri::HTML(response.body).at_css("form[action='#{path}/browser']")).to be_nil
    end
  end

  it 'shows capture and publication times from the sanitized session status in both languages' do
    captured = 2.minutes.ago
    published = 1.minute.ago
    status[:session] = { state: 'active', captured_at: captured.iso8601(6), published_at: published.iso8601(6) }
    %i[en pt_BR].each do |locale|
      I18n.with_locale(locale) do
        get path
        document = Nokogiri::HTML(response.body)
        expect(document.at_css('[data-session-time="captured_at"]')['datetime']).to eq(captured.iso8601(3))
        expect(document.at_css('[data-session-time="published_at"]')['datetime']).to eq(published.iso8601(3))
        expect(document.text).to include(
          I18n.t('super_admin.instagram_automation.captured_at'), I18n.t('super_admin.instagram_automation.published_at')
        )
      end
    end
  end

  it 'disables reconnection for an unmanaged source or an active request even when manager allows control' do
    status.merge!(operator_required: true, control_available: true, managed_session: false)
    get path
    expect(page.at_css("form[action='#{path}/reconnect'] button")['disabled']).to be_present

    %w[queued running].each do |state|
      status.merge!(managed_session: true, control: { 'state' => state, 'updated_at' => Time.current.iso8601 })
      get path
      expect(Nokogiri::HTML(response.body).at_css("form[action='#{path}/reconnect'] button")['disabled']).to be_present
    end
  end

  it 'enables reconnection only when both backend signals are true' do
    [[false, false], [true, false], [false, true], [true, true], %w[true true]].each do |operator_required, control_available|
      status.merge!(operator_required: operator_required, control_available: control_available)
      get path

      button = Nokogiri::HTML(response.body).at_css("form[action='#{path}/reconnect'] button")
      expect(button.key?('disabled')).to eq(!(operator_required == true && control_available == true))
    end
  end

  it 'shows stored session evidence without claiming remote health and renders the check time' do
    checked_at = Time.zone.parse('2026-10-04 10:00:00')
    status.merge!(config_complete: true, session: { state: 'active' }, checked_at: checked_at)
    get path

    expect(page.css('#instagram-automation time').count).to eq(1)
    expect(page.css('#instagram-automation time').map { |time| time['datetime'] }).to all(eq(checked_at.iso8601(3)))
    expect(page.text).to include(I18n.t('super_admin.instagram_automation.states.session_present.text'))
    expect(page.text).to include(I18n.t('super_admin.instagram_automation.states.configured.text'))
    expect(page.text).not_to include(I18n.t('super_admin.instagram_automation.states.healthy.label'))
  end

  it 'distinguishes the real manager heartbeat time and age from the local snapshot time' do
    checked_at = Time.zone.parse('2026-10-04 10:00:00')
    heartbeat_at = checked_at - 2.minutes
    status.merge!(checked_at: checked_at, manager_connectivity: 'healthy', manager: { 'observed_at' => heartbeat_at.iso8601 })
    travel_to(checked_at) do
      get path
      manager = page.at_css('[data-component="manager"]')
      expect(manager.at_css('time')['datetime']).to eq(heartbeat_at.iso8601(3))
      expect(manager.text).to include(I18n.t('super_admin.instagram_automation.states.heartbeat_present.text'))
      expect(manager.text).to include(I18n.t('super_admin.instagram_automation.age', age: '2 minutes'))
      observed_times = page.css('#instagram-automation time').map { |time| time['datetime'] }
      expect(observed_times).to contain_exactly(checked_at.iso8601(3), heartbeat_at.iso8601(3))
    end
  end

  it 'shows every real request state and its last update in English and Brazilian Portuguese' do
    states = %w[queued running operator_required succeeded failed]
    %i[en pt_BR].each do |locale|
      I18n.with_locale(locale) do
        states.each do |state|
          updated_at = Time.zone.parse('2026-10-04 10:00:00')
          status[:control] = { 'state' => state, 'updated_at' => updated_at.iso8601 }
          get path
          request = Nokogiri::HTML(response.body).at_css('[data-request-state]')
          expect(request['data-request-state']).to eq(state)
          expect(request.text).to include(I18n.t("super_admin.instagram_automation.requests.#{state}.label"))
          expect(request.text).to include(I18n.t("super_admin.instagram_automation.requests.#{state}.text"))
          expect(request.at_css('time')['datetime']).to eq(updated_at.iso8601(3))
          expect(response.body).not_to include('translation missing')
        end
      end
    end
  end

  it 'refreshes via GET without success flash or writes' do
    expect(Instagram::Automation::OperatorControl).not_to receive(:new)
    expect(GlobalConfigService).not_to receive(:load)
    expect { get path }.not_to change(InstallationConfig, :count)
    expect(page.at_css('.flashes')).to be_nil
  end

  it 'omits only the support widget and its operator identity while preserving application scripts and navigation' do
    expect(ChatwootHub).not_to receive(:installation_identifier)
    expect { get path }.not_to change(InstallationConfig, :count)

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(
      'window.chatwootSettings', 'window.chatwootSDK', 'window.$chatwoot.setUser', super_admin.email, super_admin.name
    )
    expect(page.css('script[src]').map { |script| script['src'] }.join(' ')).to include('superadmin')
    expect(page.at_css('[role="navigation"]')).to be_present
    expect(page.css('link[rel="stylesheet"]')).to be_present
  end

  it 'keeps the support widget on existing pages without the operational opt-out' do
    get '/super_admin/app_config', params: { config: 'instagram' }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('window.chatwootSettings', 'window.chatwootSDK', 'window.$chatwoot.setUser')
    expect(response.body).to include(super_admin.email, CGI.escapeHTML(super_admin.name))
    expect(InstallationConfig.find_by!(name: 'INSTALLATION_IDENTIFIER').value).to be_present
  end

  it 'omits the support widget when rendering invalid HTML without inserting any installation configuration' do
    expect(ChatwootHub).not_to receive(:installation_identifier)
    expect do
      post path, params: { instagram_automation: { INSTAGRAM_TESTER_APP_NAME: "Invalid\nName" } }
    end.not_to change(InstallationConfig, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).not_to include(
      'window.chatwootSettings', 'window.chatwootSDK', 'window.$chatwoot.setUser', super_admin.email, super_admin.name
    )
    expect(page.at_css('#instagram-automation [role="alert"]').text).to include(I18n.t('super_admin.instagram_automation.invalid_configuration'))
  end

  it 'links the Instagram OAuth Settings to automation while preserving its form fields' do
    get '/super_admin/app_config', params: { config: 'instagram' }

    expect(response).to have_http_status(:ok)
    expect(page.at_css("aside a[href='#{path}']")).to be_present
    expect(page.css('input[name^="app_config["]').map { |input| input['name'] }).to include(
      'app_config[INSTAGRAM_APP_ID]', 'app_config[INSTAGRAM_APP_SECRET]', 'app_config[INSTAGRAM_VERIFY_TOKEN]'
    )
    get '/super_admin/app_config', params: { config: 'google' }
    expect(Nokogiri::HTML(response.body).at_css('#instagram-automation-link-title')).to be_nil
  end

  it 'adds a separate Settings card and keeps its submenu open on the automation page' do
    get '/super_admin/settings'
    expect(response).to have_http_status(:ok)
    expect(page.css("a[href='#{path}']").count).to be >= 2

    get path
    expect(response).to have_http_status(:ok)
    expect(page.at_css("details[open] a[href='#{path}']")).to be_present
  end
end
