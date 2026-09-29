require 'rails_helper'
require 'timeout'

RSpec.describe 'Relationships and legacy writers under real PostgreSQL interleaving', type: :request do
  self.use_transactional_tests = false

  let!(:account) { create(:account) }
  let!(:legacy_admin) { create(:user, account: account, role: :administrator) }
  let!(:new_admin) { create(:user, account: account, role: :administrator) }

  let!(:legacy_headers) { legacy_admin.create_new_auth_token }
  let!(:new_headers) { new_admin.create_new_auth_token }

  before { account.enable_features!('relationships_attributes', 'custom_attributes', 'companies') }

  after do
    account.destroy!
    legacy_admin.destroy!
    new_admin.destroy!
  end

  %w[account contact company].each do |entity|
    it "preserves both writes after the legacy #{entity} request reads before the relationships commit" do
      record = entity == 'account' ? account : create(entity.to_sym, account: account)
      if entity != 'account'
        create(:custom_attribute_definition, account: account, attribute_model: "#{entity}_attribute", attribute_key: 'new_key',
                                             attribute_display_type: 'text')
      end
      base = "/api/v1/accounts/#{account.id}"
      legacy_url = entity == 'account' ? base : "#{base}/#{entity.pluralize}/#{record.id}"
      legacy_payload = entity == 'account' ? { auto_resolve_after: 90 } : { custom_attributes: { old_key: 'legacy' } }
      legacy_payload = { company: legacy_payload } if entity == 'company'
      new_url = entity == 'account' ? "#{base}/relationships/configuration" : "#{base}/relationships/#{entity}/#{record.id}/values"
      new_payload = if entity == 'account'
                      { configuration: { revision: 0,
                                         surfaces: {} } }
                    else
                      { field: { key: 'new_key', value: 'confirmed', previous: nil } }
                    end
      writer_pid = Queue.new
      writer = nil
      connection = ActiveRecord::Base.connection

      record.with_lock do
        writer = Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do |writer_connection|
            writer_pid << writer_connection.raw_connection.backend_pid
            session = ActionDispatch::Integration::Session.new(Rails.application)
            session.patch legacy_url, headers: legacy_headers, params: legacy_payload, as: :json
            session.response.status
          end
        end
        pid = writer_pid.pop(timeout: 10)
        Timeout.timeout(10) do
          loop do
            break if connection.select_value("SELECT pg_backend_pid() = ANY(pg_blocking_pids(#{Integer(pid)}))")

            raise 'Legacy request finished before the required overlap' unless writer.alive?

            sleep 0.01
          end
        end
        patch new_url, headers: new_headers, params: new_payload, as: :json
        expect(response).to have_http_status(:ok)
      end
      expect(writer.value).to eq(200)
      record.reload
      if entity == 'account'
        expect(record.settings).to include('auto_resolve_after' => 90)
        expect(record.settings.dig('relationships', 'revision')).to eq(1)
      else
        expect(record.custom_attributes).to include('old_key' => 'legacy', 'new_key' => 'confirmed')
      end
    ensure
      writer&.join(15) || writer&.kill&.join
    end
  end
end
