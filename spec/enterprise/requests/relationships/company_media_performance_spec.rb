require 'rails_helper'

RSpec.describe 'Company media bounded query performance', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:company) { create(:company, account: account) }
  let(:headers) { admin.create_new_auth_token }
  let(:url) { "/api/v1/accounts/#{account.id}/companies/#{company.id}/media" }

  it 'searches 1,000 occurrences without per-row queries and meets the predeclared local p95 target' do
    account.enable_features!('companies', 'relationships_company_media')
    inbox = create(:inbox, account: account)
    messages = Array.new(50) do
      contact = create(:contact, account: account, company: company)
      conversation = create(:conversation, account: account, contact: contact, inbox: inbox)
      create(:message, account: account, conversation: conversation, inbox: inbox, sender: contact)
    end
    blob = ActiveStorage::Blob.create_and_upload!(io: Rails.root.join('spec/assets/sample.pdf').open,
                                                  filename: 'Synthetic benchmark.pdf', content_type: 'application/pdf')
    rows = Array.new(1000) do |index|
      { account_id: account.id, message_id: messages[index % messages.length].id, file_type: Attachment.file_types.fetch('file'),
        created_at: Time.current - index.seconds, updated_at: Time.current }
    end
    rows.each { |row| Attachment.create!(row.merge(file: blob)) }

    metrics = {}
    excluded_queries = %w[SCHEMA TRANSACTION]
    [25, 50].each do |page_size|
      # Warm route/autoloading outside the timed samples; no conversion belongs to this endpoint.
      get url, headers: headers, params: { per_page: page_size, q: 'Synthetic', group: 'contact' }
      durations = []
      query_counts = []
      20.times do
        count = 0
        listener = lambda do |*args|
          payload = args.last
          count += 1 unless payload[:cached] || excluded_queries.include?(payload[:name])
        end
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        ActiveSupport::Notifications.subscribed(listener, 'sql.active_record') do
          get url, headers: headers, params: { per_page: page_size, q: 'Synthetic', group: 'contact' }
        end
        durations << ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000)
        query_counts << count
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['meta']['total']).to eq(1000)
        expect(response.parsed_body['payload'].length).to eq(page_size)
      end
      metrics[page_size] = { p95_ms: durations.sort[18].round(2), max_queries: query_counts.max, samples: durations.length }
    end
    expect(metrics[50][:max_queries] - metrics[25][:max_queries]).to be <= 2
    expect(metrics.values.map { |value| value[:p95_ms] }.max).to be < 500
    expect(Relationships::CompanyPreviewJob).not_to have_been_enqueued
    puts "RELATIONSHIPS_PERFORMANCE #{metrics.to_json}"
  end
end
