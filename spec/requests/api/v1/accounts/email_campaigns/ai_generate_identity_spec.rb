require 'rails_helper'

# "Criar com IA" with a visual identity (#1076): the composer sends the chosen kit (or a site read for
# this e-mail) and the light/dark version; the job resolves it into the prompt and records it.
RSpec.describe 'E-mail AI generation with a visual identity (#1076)', :aggregate_failures, type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:campaign) { create(:email_campaign, account: account) }
  let(:path) { "/api/v1/accounts/#{account.id}/email_campaigns/ai/generate" }
  let!(:default_kit) { create(:brand_kit, account: account, name: 'Hub2You', is_default: true) }

  around do |example|
    with_modified_env(CRM_KANBAN_ENABLED: 'true', EMAIL_CAMPAIGN_ENABLED: 'true', CRM_AI_ENABLED: 'true') { example.run }
  end

  before do
    resolver = instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'test-key' })
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(resolver)
  end

  def generate(extra = {})
    post path, params: { campaign_id: campaign.id, brief: 'Convite' }.merge(extra), headers: admin.create_new_auth_token, as: :json
  end

  def enqueued_brand
    job = ActiveJob::Base.queue_adapter.enqueued_jobs.find { |item| item['job_class'] == 'EmailCampaigns::Ai::SubmitJob' }
    ActiveJob::Arguments.deserialize(job['arguments']).last['brand']
  end

  it 'uses the default kit of the account in the light version when nothing is chosen' do
    generate

    expect(response).to have_http_status(:accepted)
    expect(enqueued_brand).to eq('kit_id' => default_kit.id, 'mode' => 'light')
  end

  it 'uses the chosen kit and the dark version' do
    other = create(:brand_kit, account: account, name: 'Autonomia')

    generate(brand_kit_id: other.id, brand_mode: 'dark')

    expect(enqueued_brand).to eq('kit_id' => other.id, 'mode' => 'dark')
  end

  it 'refuses a kit of another account or an archived one' do
    generate(brand_kit_id: create(:brand_kit).id)
    expect(response).to have_http_status(:not_found)

    archived = create(:brand_kit, account: account, archived_at: Time.current)
    generate(brand_kit_id: archived.id)
    expect(response.parsed_body['error']).to eq('brand_kit.not_found')
  end

  it 'uses a site read for this e-mail only when the reading finished' do
    import = create(:brand_import_job, account: account, status: :succeeded, result: { 'name' => 'Aurora' })
    generate(brand_import_id: import.id)
    expect(enqueued_brand).to eq('import_id' => import.id, 'mode' => 'light')

    running = create(:brand_import_job, account: account, url: 'https://b.example/', status: :failed)
    generate(brand_import_id: running.id)
    expect(response.parsed_body['error']).to eq('brand_kit_import.not_ready')
  end

  it 'generates without identity on request or when BRAND_KITS_ENABLED is off' do
    generate(brand_kit_id: 'none')
    expect(enqueued_brand).to be_nil

    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    with_modified_env(BRAND_KITS_ENABLED: 'false') { generate }
    expect(enqueued_brand).to be_nil
  end
end
