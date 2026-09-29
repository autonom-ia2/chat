require 'rails_helper'
require 'uri'

RSpec.describe 'Company media delivery', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:company) { create(:company, account: account) }
  let(:contact) { create(:contact, account: account, company: company) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:message) { create(:message, account: account, conversation: conversation, inbox: conversation.inbox, sender: contact) }
  let(:attachment) do
    message.attachments.create!(account: account, file_type: :file,
                                file: fixture_file_upload(Rails.root.join('spec/assets/sample.pdf'), 'application/pdf'))
  end
  let(:headers) { admin.create_new_auth_token }
  let(:url) { "/api/v1/accounts/#{account.id}/companies/#{company.id}/media/#{attachment.id}" }

  before { account.enable_features!('companies', 'relationships_company_media') }

  it 'serves the original through an expiring attachment URL and not a permanent public redirect' do
    get url, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.headers['Cache-Control']).to include('private', 'no-store')
    download = URI.parse(response.parsed_body.fetch('url'))
    get download.request_uri
    expect(response).to have_http_status(:ok)
    expect(response.headers['Content-Disposition']).to start_with('attachment')
    expect(response.body.byteslice(0, 5)).to eq('%PDF-')
    travel 61.seconds do
      get download.request_uri
      expect(response).to have_http_status(:not_found)
    end
  end

  it 'delivers a real JPEG preview after bounded conversion and rechecks the current company link' do
    get "#{url}/preview", headers: headers
    expect(response).to have_http_status(:accepted)
    Relationships::CompanyPreviewJob.perform_now(attachment.id, attachment.file.blob_id)
    expect(Relationships::CompanyPreviewJob.ready?(attachment.reload)).to be(true)
    get "#{url}/preview", headers: headers
    expect(response).to have_http_status(:ok)
    expect({ type: response.media_type, signature: response.body.byteslice(0, 2) }).to eq(type: 'image/jpeg', signature: "\xFF\xD8".b)
    expect(response.headers['Cache-Control']).to include('private', 'no-store')
    contact.update!(company: nil)
    get "#{url}/preview", headers: headers
    expect(response).to have_http_status(:not_found)
    get url, headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it 'keeps SVG originals as downloads instead of active inline documents' do
    attachment.file.attach(io: StringIO.new('<svg xmlns="http://www.w3.org/2000/svg"/>'), filename: 'synthetic.svg', content_type: 'image/svg+xml')
    get url, headers: headers, params: { inline: 'true' }
    expect(response).to have_http_status(:ok)
    download = URI.parse(response.parsed_body.fetch('url'))
    get download.request_uri
    expect(response.headers['Content-Disposition']).to start_with('attachment')
  end
end
