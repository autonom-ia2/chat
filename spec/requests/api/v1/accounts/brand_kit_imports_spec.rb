require 'rails_helper'

RSpec.describe 'Brand kit imports API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:path) { "/api/v1/accounts/#{account.id}/brand_kit_imports" }

  it 'enqueues an import and returns its id for polling' do
    expect do
      post path, params: { url: 'hub2you.ai' }, headers: admin.create_new_auth_token, as: :json
    end.to have_enqueued_job(BrandKits::ImportJob)

    expect(response).to have_http_status(:accepted)
    job = BrandImportJob.find(response.parsed_body['id'])
    expect(job).to have_attributes(url: 'https://hub2you.ai/', status: 'queued', user_id: admin.id)
  end

  it 'refuses an invalid URL before enqueueing' do
    post path, params: { url: 'ftp://hub2you.ai' }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to include('error_code' => 'invalid_url')
    expect(BrandImportJob.count).to eq(0)
  end

  it 'answers 409 with the running import when one is active' do
    running = create(:brand_import_job, account: account, status: :running)

    post path, params: { url: 'https://hub2you.ai' }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body).to include('error' => 'brand_kit_import.already_running', 'id' => running.id)
  end

  it 'replaces a stale active import' do
    stale = create(:brand_import_job, account: account, status: :running, created_at: 10.minutes.ago)

    post path, params: { url: 'https://hub2you.ai' }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:accepted)
    expect(stale.reload).to have_attributes(status: 'failed', error_code: 'stale')
  end

  it 'limits imports per account per hour' do
    create_list(:brand_import_job, BrandImportJob::HOURLY_LIMIT, account: account, status: :succeeded)

    post path, params: { url: 'https://hub2you.ai' }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:too_many_requests)
    expect(response.parsed_body['error']).to eq('brand_kit_import.rate_limited')
  end

  it 'returns the proposal once the import succeeded' do
    job = create(:brand_import_job, account: account, status: :succeeded, result: { 'name' => 'Hub2You' })

    get "#{path}/#{job.id}", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('id' => job.id, 'status' => 'succeeded', 'proposal' => { 'name' => 'Hub2You' })
  end

  it 'explains a failure with a translated message' do
    job = create(:brand_import_job, account: account, status: :failed, error_code: 'unsafe_url')

    get "#{path}/#{job.id}", headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body).to include('error_code' => 'unsafe_url', 'proposal' => nil)
    expect(response.parsed_body['error_message']).to be_present
  end
end
