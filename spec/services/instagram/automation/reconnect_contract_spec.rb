# rubocop:disable RSpec/SpecFilePathFormat -- Local controller/status contracts run without database setup.
require 'spec_helper'
require_relative '../../../../config/environment'

RSpec.describe SuperAdmin::InstagramAutomationsController do
  let(:control) { instance_double(Instagram::Automation::OperatorControl) }
  let(:controller) { described_class.new }
  let(:request) { ActionDispatch::TestRequest.create }
  let(:id) { SecureRandom.uuid }
  let(:queued) { { 'id' => id, 'action' => 'reconnect', 'state' => 'queued' } }

  before do
    allow(controller).to receive(:current_super_admin).and_return(instance_double(SuperAdmin, id: 42))
    controller.request = request
    controller.send(:set_response!, ActionDispatch::Response.new)
    allow(Instagram::Automation::OperatorControl).to receive(:new).and_return(control)
  end

  it 'queues and responds with accepted typed JSON' do
    request.set_header('HTTP_ACCEPT', 'application/json')
    expect(control).to receive(:enqueue).with(actor_id: 42).and_return(queued)
    with_modified_env('INSTAGRAM_TESTER_SESSION_SOURCE' => 'managed') { controller.reconnect }
    expect(controller.response.status).to eq(202)
    expect(JSON.parse(controller.response.body)).to eq('request' => queued)
  end

  it 'queues and redirects HTML to the existing panel' do
    request.set_header('HTTP_ACCEPT', 'text/html')
    expect(control).to receive(:enqueue).with(actor_id: 42).and_return(queued)
    with_modified_env('INSTAGRAM_TESTER_SESSION_SOURCE' => 'managed') { controller.reconnect }
    expect(controller.response.status).to eq(302)
    expect(controller.response.location).to end_with('/super_admin/instagram_automation')
  end

  it 'sanitizes unavailable control for both HTML and JSON' do
    allow(control).to receive(:enqueue).and_raise(Instagram::Automation::OperatorControl::Rejected)
    request.set_header('HTTP_ACCEPT', 'application/json')
    with_modified_env('INSTAGRAM_TESTER_SESSION_SOURCE' => 'managed') { controller.reconnect }
    expect(controller.response.status).to eq(503)
    expect(JSON.parse(controller.response.body)).to eq('error' => 'operator_channel_unavailable')
  end

  it 'never queues from unmanaged configuration' do
    request.set_header('HTTP_ACCEPT', 'application/json')
    expect(control).not_to receive(:enqueue)
    with_modified_env('INSTAGRAM_TESTER_SESSION_SOURCE' => 'env') { controller.reconnect }
    expect(controller.response.status).to eq(503)
  end

  it 'incorporates the manager/control facts without reading secret session content' do
    metadata = Instagram::Automation::Metadata::KEYS.index_with { '123' }
    allow(InstallationConfig).to receive(:find_by).with(name: 'DISABLE_META_INBOX_CREATION').and_return(nil)
    expect(Instagram::Automation::SessionStatus).to receive(:new).and_return(instance_double(Instagram::Automation::SessionStatus,
                                                                                             call: { state: 'missing' }))
    expect(control).to receive(:status).and_return(manager: { 'state' => 'operator_required', 'control_available' => true },
                                                   control: queued, manager_connectivity: 'operator_required',
                                                   operator_required: true, control_available: true)
    with_modified_env('INSTAGRAM_TESTER_SESSION_SOURCE' => 'managed') do
      status = Instagram::Automation::LocalStatus.new(metadata: metadata).call
      expect(status).to include(control: queued, operator_required: true, control_available: true, manager_connectivity: 'operator_required')
    end
  end
end

# rubocop:enable RSpec/SpecFilePathFormat
