require 'rails_helper'
require 'timeout'

RSpec.describe 'Widget deletion and relationships writes', :relationships_committed_fixtures, type: :request do
  self.use_transactional_tests = false

  let!(:account) { create(:account) }
  let!(:contact) { create(:contact, account: account, custom_attributes: { 'remove_me' => 'old', 'position' => 'old' }) }
  let!(:web_widget) { create(:channel_widget, account: account) }
  let!(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: web_widget.inbox) }
  let(:definition) do
    create(:custom_attribute_definition, account: account, attribute_model: 'contact_attribute',
                                         attribute_key: 'position', attribute_display_type: 'text')
  end
  let(:token) do
    Widget::TokenService.new(payload: { source_id: contact_inbox.source_id, inbox_id: web_widget.inbox.id }).generate_token
  end

  after { account.destroy! }

  it 'removes only the requested widget key after a concurrent confirmed edit' do
    definition
    decoded = Widget::TokenService.new(token: token).decode_token
    expect(decoded[:source_id]).to eq(contact_inbox.source_id)
    expect(web_widget.inbox.contact_inboxes.find_by(source_id: decoded[:source_id])&.contact_id).to eq(contact.id)
    headers = { 'X-Auth-Token' => token }
    writer_pid = Queue.new
    writer = nil
    connection = ActiveRecord::Base.connection
    contact.with_lock do
      writer = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |writer_connection|
          writer_pid << writer_connection.raw_connection.backend_pid
          session = ActionDispatch::Integration::Session.new(Rails.application)
          session.post "/api/v1/widget/contact/destroy_custom_attributes?website_token=#{web_widget.website_token}",
                       headers: headers, params: { custom_attributes: ['remove_me'] }, as: :json
          session.response.status
        end
      end
      pid = writer_pid.pop(timeout: 10)
      Timeout.timeout(10) do
        until connection.select_value("SELECT pg_backend_pid() = ANY(pg_blocking_pids(#{Integer(pid)}))")
          raise "Widget request finished with HTTP #{writer.value} before reaching the contact lock" unless writer.alive?

          sleep 0.01
        end
      end
      Relationships::ValuePatch.new(contact, 'contact_attribute').update!(
        'key' => 'position', 'value' => 'confirmed', 'previous' => 'old'
      )
    end
    expect(writer.value).to eq(200)
    expect(contact.reload.custom_attributes).to eq('position' => 'confirmed')
  ensure
    writer&.join(15) || writer&.kill&.join
  end
end
