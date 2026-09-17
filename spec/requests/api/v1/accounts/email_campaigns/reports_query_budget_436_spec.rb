require 'rails_helper'

RSpec.describe 'Email campaign list query budget #436', :aggregate_failures, type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:headers) { admin.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/email_campaigns/campaigns" }

  statuses = %w[sent paused sending].freeze
  sizes = %w[one all].freeze
  %w[shadow enforce].each do |mode|
    statuses.each do |status|
      it "bounds actual GET SQL for 1 versus 20 #{status} campaigns in #{mode}" do
        with_modified_env CRM_KANBAN_ENABLED: 'true', EMAIL_CAMPAIGN_ENABLED: 'true', EMAIL_REPUTATION_MODE: 'shadow',
                          EMAIL_CAMPAIGN_HYGIENE_MODE: mode, EMAIL_REPUTATION_PROVIDER_MONITOR: 'false',
                          EMAIL_REPUTATION_PROVIDER_BLOCK: 'false' do
          identity = create(:email_sender_identity, account: account)
          campaigns = Array.new(20) do |index|
            row = create(:email_campaign, account: account, sender_identity: identity, status: status,
                                          name: index.zero? ? 'Budget one' : "Budget #{index}")
            create(:email_campaign_recipient, email_campaign: row, preflight_status: 'valid',
                                              preflight_checked_at: Time.current, preflight_valid_until: 1.day.from_now)
            create(:email_campaign_recipient, email_campaign: row, status: :sent, sent_at: 1.hour.ago)
            row.email_campaign_import_issues.create!(row_number: 2, raw_address: 'duplicate@example.org', reason_code: 'duplicate')
            row.email_campaign_imports.create!(status: index.odd? ? :processing : :completed)
            row
          end
          # Warm route/template/schema initialization before measuring both real HTTP reads.
          sizes.each { |size| get base, params: { q: size == 'one' ? 'Budget one' : 'Budget' }, headers: headers, as: :json }
          reads = sizes.map do |size|
            sql = []
            subscriber = ->(*args) { sql << args.last[:sql] unless args.last[:name] == 'SCHEMA' }
            ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') do
              get base, params: { q: size == 'one' ? 'Budget one' : 'Budget' }, headers: headers, as: :json
            end
            expect(response).to have_http_status(:ok)
            rows = response.parsed_body.dig('payload', 'campaigns')
            expect(rows.size).to eq(size == 'one' ? 1 : 20)
            expect(rows).to all(include('preflight' => include('historical_sent' => 1, 'issues_count' => 1, 'recipients_total' => 2)))
            expect(rows.find { |row| row['id'] == campaigns.first.id }.dig('protection', 'capabilities', 'resume')).to eq(status == 'paused')
            expect(rows.find { |row| row['id'] == campaigns.second.id }.dig('preflight', 'can_recheck')).to be(false) if size == 'all'
            expect(sql.grep(/email_campaign|email_suppression|email_reputation/i).grep(/FOR (?:UPDATE|SHARE)/i)).to be_empty
            sql.grep(/\ASELECT/i) # Include cached SQL: query caching must not hide per-campaign work.
          end
          expect(reads.last.size).to be <= reads.first.size + 2
          expect(reads.last.grep(/FROM "email_campaign_recipients"/i).size).to be <= 4
          expect(reads.last.grep(/FROM "email_campaign_import_issues"/i).size).to eq(1)
        end
      end
    end
  end
end
