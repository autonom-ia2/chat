# rubocop:disable RSpec/SpecFilePathFormat -- Offline controller contracts do not require a database.
require 'spec_helper'
require_relative '../../../../config/environment'
require 'action_controller/test_case'

RSpec.describe SuperAdmin::InstagramAutomationsController do
  let(:controller) { described_class.new }
  let(:request) { ActionDispatch::TestRequest.create }
  let(:control) { instance_double(Instagram::Automation::OperatorControl) }
  let(:request_id) { SecureRandom.uuid }
  let(:active) do
    { 'id' => request_id, 'actor_id' => 42, 'state' => 'running', 'created_at' => 2.minutes.ago.utc.iso8601(3) }
  end
  let(:environment) do
    {
      'INSTAGRAM_TESTER_SESSION_SOURCE' => 'managed', 'INSTAGRAM_TESTER_RUNTIME_STACK' => 'hub2you',
      'INSTAGRAM_TESTER_OPERATOR_BROWSER_URL' => 'https://gateway.invalid/hub2you/',
      'INSTAGRAM_TESTER_OPERATOR_BROWSER_SIGNING_KEY' => 'ab' * 32, 'FRONTEND_URL' => 'https://hub.invalid'
    }
  end

  around do |example|
    previous = described_class.allow_forgery_protection
    described_class.allow_forgery_protection = true
    with_modified_env(environment) { example.run }
  ensure
    described_class.allow_forgery_protection = previous
  end

  before do
    request.set_header('REQUEST_METHOD', 'POST')
    request.set_header('HTTP_ACCEPT', 'text/html')
    request.session = ActionController::TestSession.new
    controller.request = request
    controller.send(:set_response!, ActionDispatch::Response.new)
    allow(controller).to receive(:authenticate_super_admin!)
    allow(controller).to receive(:current_super_admin).and_return(instance_double(SuperAdmin, id: 42))
    allow(Instagram::Automation::OperatorControl).to receive(:new).and_return(control)
    allow(control).to receive(:status).and_return(control: active)
    allow(ViteRuby.instance.manifest).to receive(:resolve_entries).with('superadmin', type: :javascript).and_return(
      stylesheets: ['/vite-test/assets/superadmin-synthetic.css']
    )
    controller.params = ActionController::Parameters.new(authenticity_token: controller.send(:form_authenticity_token))
  end

  it 'runs Super Admin authentication and CSRF before rendering a POST grant form with no token in any URL' do
    expect(controller).to receive(:authenticate_super_admin!)
    expect(control).not_to receive(:enqueue)
    controller.process(:browser)

    expect(controller.response.status).to eq(200)
    expect(controller.response.headers['Cache-Control']).to eq('no-store')
    expect(controller.response.headers['Referrer-Policy']).to eq('strict-origin')
    expect(controller.response.headers['Location']).to be_nil
  end

  it 'renders a grant form carrying the ticket only in its POST body' do
    controller.process(:browser)
    page = Nokogiri::HTML(controller.response.body)
    form = page.at_css('form')
    expect(form['action']).to eq('https://gateway.invalid/hub2you/grant')
    expect(form['method']).to eq('post')
    expect(form.at_css('input[name="authenticity_token"]')).to be_nil
    expect(form.css('[name]').map { |field| field['name'] }).to eq(['ticket'])
    ticket = form.at_css('input[name="ticket"]')['value']
    claims = JWT.decode(ticket, ['ab' * 32].pack('H*'), true, algorithm: 'HS256').first
    expect(claims).to include('sub' => '42', 'request_id' => request_id)
    expect(page.css('[href], [src], [action]').map { |node| node['href'] || node['src'] || node['action'] }.join).not_to include(ticket)
  end

  it 'omits scripts and the support widget from the ticket page' do
    controller.process(:browser)
    page = Nokogiri::HTML(controller.response.body)
    expect(page.at_css('meta[name="referrer"]')['content']).to eq('strict-origin')
    expect(page.css('script')).to be_empty
    expect(controller.response.body).not_to include('window.chatwootSDK')
  end

  it 'renders the panel browser POST and public session timestamps in both supported languages' do
    status = {
      global_gate: false, config_complete: false,
      session: { state: 'active', published_at: '2026-10-05T12:01:00.000Z', captured_at: '2026-10-05T12:00:00.000Z' },
      proxy: { configured: false, valid: false }, coordination: { configured: false }, meta_creation_disabled: false,
      manager_connectivity: 'unknown', meta_connectivity: 'unknown', checked_at: nil,
      managed_session: true, operator_browser_configured: true, control: active.merge('updated_at' => Time.current.iso8601)
    }
    controller.instance_variable_set(:@metadata, Instagram::Automation::Metadata::KEYS.index_with { '' })
    controller.instance_variable_set(:@status, status)
    %i[en pt_BR].each do |locale|
      I18n.with_locale(locale) do
        page = Nokogiri::HTML(controller.render_to_string(template: 'super_admin/instagram_automation/show', layout: false))
        form = page.at_css('form[action="/super_admin/instagram_automation/browser"]')
        expect(form['method']).to eq('post')
        expect(form['target']).to eq('_blank')
        expect(form.at_css('input[name="authenticity_token"]')).to be_present
        expect(page.at_css('[data-session-time="published_at"]')['datetime']).to eq('2026-10-05T12:01:00.000Z')
        expect(page.at_css('[data-session-time="captured_at"]')['datetime']).to eq('2026-10-05T12:00:00.000Z')
        expect(page.text).to include(I18n.t('super_admin.instagram_automation.remote_browser_hint'))
        expect(page.text).not_to include('translation missing')
      end
    end
  end

  it 'hides browser access without changing reconnect availability when another actor owns the request' do
    status = {
      managed_session: true, operator_browser_configured: true, operator_required: true, control_available: true,
      control: active.merge('actor_id' => 43)
    }
    helper = controller.view_context
    expect(helper.instagram_automation_browser_available?(status)).to be(false)
    status[:control] = nil
    expect(helper.instagram_automation_browser_available?(status)).to be(false)
    expect(helper.instagram_automation_reconnect_available?(status)).to be(true)
  end

  it 'rejects missing and invalid CSRF before reading control or issuing a ticket' do
    request.set_header('HTTP_ACCEPT', 'application/json')
    expect(control).not_to receive(:status)
    expect(Instagram::Automation::OperatorBrowserTicket).not_to receive(:new)
    [nil, 'invalid-synthetic-token'].each do |token|
      controller.params = ActionController::Parameters.new(authenticity_token: token)
      controller.process(:browser)
      expect(controller.response.status).to eq(422)
      expect(JSON.parse(controller.response.body)).to eq('error' => 'invalid_request')
    end
  end

  it 'rejects actor, request or ticket input instead of trusting client identity' do
    request.set_header('HTTP_ACCEPT', 'application/json')
    expect(control).not_to receive(:status)
    controller.params = controller.params.merge(actor_id: 42, request_id: request_id, ticket: 'synthetic-do-not-echo')
    controller.process(:browser)
    expect(controller.response.status).to eq(422)
    expect(JSON.parse(controller.response.body)).to eq('error' => 'invalid_configuration')
    expect(controller.response.body).not_to include('synthetic-do-not-echo')
  end

  it 'fails with a fixed message for another actor, absent request, expired request or completed request' do
    [nil, active.merge('actor_id' => 43), active.merge('state' => 'succeeded'),
     active.merge('created_at' => 1.hour.ago.utc.iso8601(3))].each do |value|
      allow(control).to receive(:status).and_return(control: value)
      controller.process(:browser)
      expect(controller.response.status).to eq(503)
      expect(controller.response.body).to eq(I18n.t('super_admin.instagram_automation.operator_browser_unavailable'))
      expect(controller.response.body).not_to include(request_id)
    end
  end

  it 'routes only POST browser and filters ticket values from request logs' do
    expect(Rails.application.routes.recognize_path('/super_admin/instagram_automation/browser', method: :post))
      .to include(controller: 'super_admin/instagram_automations', action: 'browser')
    expect do
      Rails.application.routes.recognize_path('/super_admin/instagram_automation/browser', method: :get)
    end.to raise_error(ActionController::RoutingError)
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    expect(filter.filter('ticket' => 'synthetic-do-not-log')).to eq('ticket' => '[FILTERED]')
  end
end
# rubocop:enable RSpec/SpecFilePathFormat
