require 'rails_helper'

# O que as telas de "Trazer meu modelo" leem e fazem (#1099, entrega C): o passo em que a preparação está, a prévia do
# original limpo, o que dá para corrigir, as correções em si e a importação que a pessoa deixou para ver depois.
RSpec.describe 'Email template imports screens', :aggregate_failures, type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:headers) { admin.create_new_auth_token }
  let(:path) { "/api/v1/accounts/#{account.id}/email_campaigns/template_imports" }
  let(:png) { Base64.decode64('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==') }
  let(:html) do
    <<~HTML
      <html><head><title>Novidades de outubro</title></head><body>
        <table width="600" align="center"><tr><td>
          <img src="https://cdn.example.com/logo.png" alt="Logo da loja" width="200">
          <p style="font-size:16px">Olá, {{ nome }}! Seu cupom: {{ lead.cupom }}</p>
          <a href="https://loja.example.com/colecao" style="background:#1f6feb;color:#ffffff;padding:12px 24px">Ver coleção</a>
        </td></tr></table>
      </body></html>
    HTML
  end
  let(:fetch_ok) { true }

  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true', EMAIL_CAMPAIGN_ENABLED: 'true', FRONTEND_URL: 'https://app.exemplo.com.br' do
      example.run
    end
  end

  before do
    account.enable_features!('email_template_import')
    allow(SafeFetch).to receive(:fetch) do |_url, **_options, &block|
      raise SafeFetch::HttpError.new('404', status: 404) unless fetch_ok

      file = Tempfile.new('imports-spec', binmode: true)
      file.write(png)
      file.rewind
      block.call(SafeFetch::Result.new(tempfile: file, filename: 'x', content_type: 'image/png'))
    ensure
      file&.close!
    end
    allow(EmailCampaigns::Import::ImageCompressor).to receive(:call) do |bytes, content_type|
      EmailCampaigns::Import::ImageCompressor::Output.new(bytes: bytes, content_type: content_type, extension: 'png', compressed: false)
    end
  end

  def paste(content = html)
    perform_enqueued_jobs(only: EmailCampaigns::Import::RunJob) do
      post path, params: { source_kind: 'paste', content: content }, headers: headers
    end
    response.parsed_body.fetch('id')
  end

  def show(id)
    get "#{path}/#{id}", headers: headers, as: :json
    response.parsed_body
  end

  def upload
    file = Tempfile.new(['troca', '.png'], binmode: true)
    file.write(png)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, 'image/png', true, original_filename: 'troca.png')
  end

  it 'tells the step of the preparation while it runs' do
    post path, params: { source_kind: 'paste', content: html }, headers: headers
    body = show(response.parsed_body['id'])

    expect(body['status']).to eq('queued')
    expect(body['progress']).to eq({})
    expect(body).to include('preview_html' => nil, 'result_mjml' => nil, 'targets' => nil)
  end

  it 'hands back the cleaned original next to the result, with the images of the import only and no links' do
    body = show(paste)

    expect(body['progress']).to include('step' => 'done', 'images_total' => 1, 'images_done' => 1)
    preview = Nokogiri::HTML5(body['preview_html'])
    expect(preview.text).to include('Seu cupom')
    expect(preview.css('img').pluck('src')).to all(start_with('https://app.exemplo.com.br/rails/active_storage/blobs/'))
    expect(preview.css('[href]')).to be_empty
    expect(body['targets']).to eq('images' => [], 'parts' => [], 'fields' => ['cupom'])
    expect(body['fixes']).to eq([])
  end

  describe 'fixing what blocks the saving' do
    let(:fetch_ok) { false }

    it 'solves each warning on the server copy and then saves' do
      id = paste
      body = show(id)
      expect(body['blocking'].pluck('code')).to contain_exactly('image_missing', 'unknown_fields')
      expect(body['targets']['images']).to eq([{ 'index' => 0, 'kind' => 'image', 'alt' => 'Logo da loja' }])

      post "#{path}/#{id}/fix", params: { kind: 'image', target: 0, choice: 'upload', file: upload }, headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['blocking'].pluck('code')).to eq(['unknown_fields'])

      post "#{path}/#{id}/fix", params: { kind: 'field', target: 'cupom', choice: 'text', value: 'OUTUBRO10' }, headers: headers, as: :json
      expect(response.parsed_body).to include('blocking' => [], 'status' => 'ready')
      expect(response.parsed_body['fixes'].pluck('code')).to eq(%w[image_missing unknown_fields])
      expect(response.parsed_body['result_mjml']).to include('Seu cupom: OUTUBRO10')

      post "#{path}/#{id}/save", params: { name: 'Outubro' }, headers: headers
      expect(response).to have_http_status(:created)
      expect(EmailCampaignTemplateImport.find(id).preview_html).to be_nil
    end

    it 'answers a code the screen explains, and changes nothing' do
      id = paste
      before = EmailCampaignTemplateImport.find(id).result_mjml

      post "#{path}/#{id}/fix", params: { kind: 'field', target: 'cupom', choice: 'text', value: '{{ email }}' }, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'email_template_import.text_invalid')
      expect(EmailCampaignTemplateImport.find(id).result_mjml).to eq(before)
    end

    it 'needs campaign_manage and the flag' do
      id = paste
      agent = create(:user, account: account, role: :agent)
      post "#{path}/#{id}/fix", params: { kind: 'image', target: 0, choice: 'remove' }, headers: agent.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)

      account.disable_features!('email_template_import')
      post "#{path}/#{id}/fix", params: { kind: 'image', target: 0, choice: 'remove' }, headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'coming back later' do
    it 'answers the last import of this person that is still running or waiting to be seen' do
      get path, headers: headers
      expect(response.parsed_body).to eq('payload' => [])

      id = paste(html.sub(' Seu cupom: {{ lead.cupom }}', ''))
      other = create(:user, account: account, role: :administrator)
      EmailCampaignTemplateImport.create!(account: account, user: other, source_kind: 'paste', status: 'failed')

      get path, headers: headers
      expect(response.parsed_body['payload'].pluck('id', 'status')).to eq([[id, 'ready']])
      expect(response.parsed_body['payload'].first).not_to include('result_mjml', 'preview_html')

      post "#{path}/#{id}/save", params: { name: 'Outubro' }, headers: headers
      get path, headers: headers
      expect(response.parsed_body).to eq('payload' => [])
    end
  end
end
