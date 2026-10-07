require 'rails_helper'

# "Ajustar com IA" (#1095): the e-mail on the screen and what the person wants changed go to the model; the
# result comes back as a before/after proposal the editor applies or discards. Provider is a double.
RSpec.describe 'E-mail campaign AI adjustment (#1095)', :aggregate_failures, type: :request do
  include EmailAdjustFixture
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:campaign) { create(:email_campaign, account: account, status: :draft, body_mjml: adjust_base_mjml) }
  let(:client) { instance_double(Crm::Ai::ResponsesClient, delete: true) }
  let(:request_text) { 'Deixe o botão verde e tire a seção de perguntas' }
  let(:base_url) { "/api/v1/accounts/#{account.id}/email_campaigns/ai" }

  before do
    allow(EmailCampaigns::Config).to receive(:enabled?).and_return(true)
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
    resolver = instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'test-key' })
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(resolver)
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
    allow(client).to receive(:create_background).and_return(id: 'resp_1', status: 'queued')
    allow(EmailCampaigns::Ai::Broadcaster).to receive(:ready)
  end

  after { EmailCampaigns::Ai::Adjustment.clear(campaign) }

  def adjust(base_mjml = adjust_base_mjml)
    post "#{base_url}/generate", params: { campaign_id: campaign.id, brief: request_text, placeholders: %w[nome],
                                           base_mjml: base_mjml }, headers: admin.create_new_auth_token, as: :json
  end

  def status
    get "#{base_url}/campaigns/#{campaign.id}/status", headers: admin.create_new_auth_token, as: :json
    response.parsed_body
  end

  it 'sends the screen e-mail and the request, then shows before and after until the person decides' do
    screen = adjust_base_mjml.sub('Perguntas frequentes', 'Dúvidas (editado, sem salvar)')
    perform_enqueued_jobs(only: EmailCampaigns::Ai::SubmitJob) { adjust(screen) }

    expect(response).to have_http_status(:accepted)
    expect(client).to have_received(:create_background) do |args|
      expect(args[:schema]).to eq(EmailCampaigns::Ai::EditPromptBuilder::SCHEMA)
      expect(args[:tools]).to be_nil
      text = args[:input].first[:content].first[:text]
      expect(text).to include(request_text, 'Dúvidas (editado, sem salvar)', '<<<BLOCO b2')
    end

    answer = { outcome: 'changed', reason: '', summary: 'Deixei o botão verde e tirei as perguntas.',
               blocks: [{ keep: '', mjml: adjust_hero(button_color: '#15803d') }] }
    allow(client).to receive(:retrieve).and_return(status: 'completed', model: 'gpt-6.1-sol', text: answer.to_json, usage: {})
    EmailCampaigns::Ai::PollJob.perform_now(campaign.id, campaign.reload.ai_generation_token, 'resp_1', 0)

    body = status
    expect(body['ai_status']).to eq('ready')
    expect(body['ai_adjustment']).to include('status' => 'proposed', 'summary' => 'Deixei o botão verde e tirei as perguntas.')
    expect(body['ai_adjustment']['base']).to include('Dúvidas (editado, sem salvar)')
    expect(body['ai_adjustment']['mjml']).to include('#15803d')
    expect(body['ai_adjustment'].keys).not_to include('input', 'instructions', 'token')
    expect(campaign.reload.body_mjml).to include('Perguntas frequentes')

    delete "#{base_url}/campaigns/#{campaign.id}/adjustment", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:no_content)
    expect(status['ai_adjustment']).to be_nil
  end

  it 'refuses an e-mail too large to adjust before queueing anything' do
    adjust('x' * 120_001)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('email_campaign.base_mjml_too_large')
    expect(campaign.reload.ai_status).to eq('idle')
  end

  it 'fails with a plain code when the screen e-mail cannot be split into blocks' do
    perform_enqueued_jobs(only: EmailCampaigns::Ai::SubmitJob) { adjust('<mj-section><mj-column></mj-column></mj-section>') }

    expect(campaign.reload.ai_status).to eq('failed')
    expect(campaign.ai_error).to eq('adjust_unreadable')
    expect(client).not_to have_received(:create_background)
  end

  it 'keeps generating from scratch when there is no screen e-mail' do
    perform_enqueued_jobs(only: EmailCampaigns::Ai::SubmitJob) { adjust(nil) }

    expect(client).to have_received(:create_background) do |args|
      expect(args[:schema]).to eq(EmailCampaigns::Ai::Generator::GENERATE_SCHEMA)
      expect(args[:tools]).to eq(Crm::Ai::WebSearch.tools)
    end
    expect(EmailCampaigns::Ai::Adjustment.presented(campaign, campaign.reload.ai_generation_token)).to be_nil
  end
end
