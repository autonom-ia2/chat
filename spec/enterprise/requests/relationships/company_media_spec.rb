require 'rails_helper'

RSpec.describe 'Company media access', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:company) { create(:company, account: account) }
  let(:contact) { create(:contact, account: account, company: company) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:message) { create(:message, account: account, conversation: conversation, message_type: :incoming) }
  let(:attachment) do
    message.attachments.create!(account: account,
                                file: fixture_file_upload(Rails.root.join('spec/assets/sample.png'), 'image/png'))
  end
  let(:url) { "/api/v1/accounts/#{account.id}/companies/#{company.id}/media" }

  before { account.enable_features!('companies', 'relationships_company_media') }

  it 'denies count, filename, original and preview outside the authorized conversation scope' do
    attachment
    headers = agent.create_new_auth_token
    get url, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['meta']['total']).to eq(0)
    expect(response.parsed_body['payload']).to eq([])
    get "#{url}/#{attachment.id}", headers: headers
    expect(response).to have_http_status(:not_found)
    get "#{url}/#{attachment.id}/preview", headers: headers
    expect(response).to have_http_status(:not_found)
    get "#{url}/contacts", headers: headers
    expect(response.parsed_body).to eq([])
  end

  it 'preserves distinct occurrences and the real sender, without exposing storage URLs in the list' do
    attachment
    outgoing = create(:message, account: account, conversation: conversation, message_type: :outgoing, sender: admin)
    outgoing.attachments.create!(account: account,
                                 file: fixture_file_upload(Rails.root.join('spec/assets/sample.png'), 'image/png'))
    get url, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
    rows = response.parsed_body['payload']
    expect(rows.length).to eq(2)
    expect(rows.pluck('id').uniq.length).to eq(2)
    expect(rows.first['sender']).to include('type' => 'User', 'name' => admin.name)
    expect(rows.first['contact']['id']).to eq(contact.id)
    expect(response.body).not_to include('data_url', 'thumb_url', 'rails/active_storage')
    expect(response.headers['Cache-Control']).to include('no-store')
  end

  it 'rejects company access when Companies or the media flag is disabled' do
    account.disable_features!('companies')
    get url, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:forbidden)
    account.enable_features!('companies')
    account.disable_features!('relationships_company_media')
    get url, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:forbidden)
  end

  it 'denies a different account even when both features are enabled' do
    stranger = create(:user, role: :administrator)
    get url, headers: stranger.create_new_auth_token
    expect(response).to have_http_status(:unauthorized).or have_http_status(:forbidden)
  end

  it 'searches past the first page and uses deterministic global grouping' do
    26.times do
      message.attachments.create!(account: account,
                                  file: fixture_file_upload(Rails.root.join('spec/assets/sample.png'), 'image/png'))
    end
    oldest = Attachment.where(message: message).order(:id).first
    oldest.file.blob.update!(filename: 'unique-old-file.png')
    get url, headers: admin.create_new_auth_token, params: { q: 'unique-old', group: 'contact' }
    expect(response.parsed_body['meta']['total']).to eq(1)
    expect(response.parsed_body['payload'].pluck('id')).to eq([oldest.id])
    get url, headers: admin.create_new_auth_token, params: { group: 'contact', page: 2 }
    expect(response.parsed_body['payload'].length).to eq(1)
  end

  it 'applies custom-role restrictions to metadata and thumbnails' do
    attachment
    role = create(:custom_role, account: account, permissions: ['conversation_participating_manage'])
    agent.account_users.find_by!(account: account).update!(custom_role: role)
    create(:inbox_member, user: agent, inbox: conversation.inbox)
    get url, headers: agent.create_new_auth_token
    expect(response.parsed_body['meta']['total']).to eq(0)
    get "#{url}/#{attachment.id}/preview", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:not_found)
    conversation.update!(assignee: agent)
    get url, headers: agent.create_new_auth_token
    expect(response.parsed_body['meta']['total']).to eq(1)
  end

  it 'does not grow SQL queries per media occurrence or generate previews during listing' do
    blob = attachment.file.blob
    49.times { message.attachments.create!(account: account, file: blob) }
    headers = admin.create_new_auth_token
    counts = [25, 50].map do |size|
      statements = []
      subscriber = lambda do |*args|
        payload = args.last
        statements << payload[:sql] if payload[:sql].start_with?('SELECT') && payload[:name] != 'SCHEMA'
      end
      ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') do
        get url, headers: headers, params: { per_page: size }
      end
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['payload'].length).to eq(size)
      statements.length
    end
    expect(counts.last).to be <= counts.first + 2
    expect(Relationships::CompanyPreviewJob).not_to have_been_enqueued
  end

  it 'rejects array-shaped contact search instead of coercing it' do
    get "#{url}/contacts", headers: admin.create_new_auth_token, params: { q: ['invalid'] }
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'includes private note attachments only inside an authorized conversation' do
    message.update!(private: true, message_type: :outgoing)
    attachment
    get url, headers: admin.create_new_auth_token
    expect(response.parsed_body['payload'].pluck('id')).to eq([attachment.id])
    get url, headers: agent.create_new_auth_token
    expect(response.parsed_body['meta']['total']).to eq(0)
    get "#{url}/#{attachment.id}/preview", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end

  it 'never fetches or lists external attachments and preserves the conversation fallback' do
    message.attachments.create!(account: account, file_type: 'file', external_url: 'https://example.test/external.pdf')
    expect(Relationships::PreviewRenderer).not_to receive(:new)
    get url, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['payload']).to eq([])
  end

  it 'groups two contacts globally across the page boundary' do
    blob = attachment.file.blob
    25.times { message.attachments.create!(account: account, file: blob) }
    second_contact = create(:contact, account: account, company: company)
    second_conversation = create(:conversation, account: account, contact: second_contact)
    second_message = create(:message, account: account, conversation: second_conversation)
    last_attachment = second_message.attachments.create!(account: account, file: blob)
    headers = admin.create_new_auth_token
    get url, headers: headers, params: { group: 'contact', page: 1 }
    expect(response.parsed_body['payload'].map { |row| row.dig('contact', 'id') }.uniq).to eq([contact.id])
    get url, headers: headers, params: { group: 'contact', page: 2 }
    rows = response.parsed_body['payload']
    expect(rows.map { |row| row.dig('contact', 'id') }).to eq([contact.id, second_contact.id])
    expect(rows.last['id']).to eq(last_attachment.id)
    expect(response.parsed_body['meta']['total']).to eq(27)
  end
end
