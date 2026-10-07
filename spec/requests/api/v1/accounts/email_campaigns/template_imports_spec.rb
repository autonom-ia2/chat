require 'rails_helper'

# Importar modelo de e-mail (#1099, entrega B): o fluxo colar/arquivo/endereço → job → acompanhamento → salvar em
# "Meus modelos", com a flag, a permissão campaign_manage, a trava por conta e o limite de pedidos.
RSpec.describe 'Email template imports', :aggregate_failures, type: :request do
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
          <p style="font-size:16px">Olá, {{ nome }}! Chegou a coleção nova.</p>
          <a href="https://loja.example.com/colecao" style="background:#1f6feb;color:#ffffff;padding:12px 24px">Ver coleção</a>
        </td></tr></table>
      </body></html>
    HTML
  end
  let(:fetched) { [] }

  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true', EMAIL_CAMPAIGN_ENABLED: 'true', FRONTEND_URL: 'https://app.exemplo.com.br' do
      example.run
    end
  end

  before do
    account.enable_features!('email_template_import')
    allow(SafeFetch).to receive(:fetch) do |url, **options, &block|
      fetched << [url, options]
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

  def create_import(params)
    perform_enqueued_jobs(only: EmailCampaigns::Import::RunJob) { post path, params: params, headers: headers }
  end

  def paste(content = html)
    create_import(source_kind: 'paste', content: content)
    response.parsed_body.fetch('id')
  end

  def show(id)
    get "#{path}/#{id}", headers: headers, as: :json
    response.parsed_body
  end

  def upload(bytes, name, type)
    file = Tempfile.new(['upload', File.extname(name)], binmode: true)
    file.write(bytes)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, type, true, original_filename: name)
  end

  def zip(entries)
    Zip::OutputStream.write_buffer do |stream|
      entries.each do |name, content|
        stream.put_next_entry(name)
        stream.write(content)
      end
    end.string
  end

  describe 'feature flag and permissions' do
    it 'answers 404 everywhere while the account does not have the flag' do
      import = EmailCampaignTemplateImport.create!(account: account, source_kind: 'paste', status: 'ready', result_mjml: '<mjml></mjml>')
      account.disable_features!('email_template_import')

      post path, params: { source_kind: 'paste', content: html }, headers: headers
      expect(response).to have_http_status(:not_found)
      get "#{path}/#{import.id}", headers: headers
      expect(response).to have_http_status(:not_found)
      post "#{path}/#{import.id}/save", params: { name: 'X' }, headers: headers
      expect(response).to have_http_status(:not_found)
      expect(EmailCampaignTemplateImport.count).to eq(1)
    end

    it 'requires campaign_manage: a plain agent cannot import, follow or save' do
      agent = create(:user, account: account, role: :agent)
      import = EmailCampaignTemplateImport.create!(account: account, source_kind: 'paste', status: 'ready', result_mjml: '<mjml></mjml>')

      post path, params: { source_kind: 'paste', content: html }, headers: agent.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)
      get "#{path}/#{import.id}", headers: agent.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)
      post "#{path}/#{import.id}/save", params: { name: 'X' }, headers: agent.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)
    end

    it 'never shows an import of another account' do
      foreign = EmailCampaignTemplateImport.create!(account: create(:account), source_kind: 'paste')

      get "#{path}/#{foreign.id}", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'pasting' do
    it 'imports in the background and hands back editable MJML whose images live at permanent public addresses' do
      create_import(source_kind: 'paste', content: html)

      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body).to include('status' => 'queued', 'source_kind' => 'paste')

      body = show(response.parsed_body['id'])
      expect(body['status']).to eq('ready')
      expect(body['result_mjml']).to include('<mjml>', 'Chegou a coleção nova', '{{ nome }}', 'footer-locked')
      expect(body['result_mjml']).not_to include('cdn.example.com')
      expect(fetched.map(&:first)).to eq(['https://cdn.example.com/logo.png'])
      expect(body['report']).to include('version' => 1, 'source_kind' => 'paste', 'title' => 'Novidades de outubro')
      expect(body['report']['warnings']).to include(hash_including('code' => 'images_copied', 'severity' => 'info'))
      expect(body['blocking']).to eq([])
      expect(EmailCampaignTemplateImport.find(body['id']).source).not_to be_attached
    end

    it 'refuses more than 500 KB or nothing at all, before creating anything' do
      post path, params: { source_kind: 'paste', content: 'a' * (500.kilobytes + 1) }, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'email_template_import.too_large')

      post path, params: { source_kind: 'paste', content: '   ' }, headers: headers
      expect(response.parsed_body).to eq('error' => 'email_template_import.empty')

      post path, params: { source_kind: 'fax' }, headers: headers
      expect(response.parsed_body).to eq('error' => 'email_template_import.invalid_source_kind')
      expect(EmailCampaignTemplateImport.count).to eq(0)
    end

    it 'records a failure with a code and none of the client markup' do
      id = paste('<html><body>   </body></html>')

      body = show(id)
      expect(body).to include('status' => 'failed', 'error_code' => 'empty', 'result_mjml' => nil)
    end
  end

  describe 'sending a file' do
    it 'imports an .html file' do
      create_import(source_kind: 'file', file: upload(html, 'modelo.html', 'text/html'))

      expect(show(response.parsed_body['id'])).to include('status' => 'ready', 'source_kind' => 'file')
    end

    it 'imports a .zip using its own images by their relative name' do
      page = html.sub('https://cdn.example.com/logo.png', 'imagens/logo.png')
                 .sub('coleção nova.', 'coleção nova. <a href="sobre.html">Saiba mais</a>')
      create_import(source_kind: 'file', file: upload(zip('modelo.html' => page, 'imagens/logo.png' => png), 'modelo.zip', 'application/zip'))

      body = show(response.parsed_body['id'])
      expect(body['status']).to eq('ready')
      expect(fetched).to be_empty
      expect(body['result_mjml']).to include('https://app.exemplo.com.br/rails/active_storage/blobs/redirect/')
      expect(body['result_mjml']).not_to include(EmailCampaigns::Import::ZipReader::BASE_URL)
      expect(body['result_mjml']).to include('Saiba mais')
      expect(body['report']['warnings']).to include(hash_including('code' => 'link_removed'))
    end

    it 'finds the images of a .zip whose names have spaces and accents' do
      page = html.sub('https://cdn.example.com/logo.png', '../img/minha foto.png')
                 .sub('</td>', '<img src="../img/promoção.png" alt="Promoção" width="200"></td>')
      files = { 'pasta/modelo.html' => page, 'img/minha foto.png' => png, 'img/promoção.png' => png }
      create_import(source_kind: 'file', file: upload(zip(files), 'modelo.zip', 'application/zip'))

      body = show(response.parsed_body['id'])
      expect(body['status']).to eq('ready')
      expect(body['report']['images'].pluck('status')).to eq(%w[copied copied])
      expect(body['blocking']).to eq([])
    end

    it 'keeps the accents of an .html saved in the western encoding' do
      latin = html.sub('<head>', '<head><meta charset="iso-8859-1">').encode(Encoding::Windows_1252).b
      create_import(source_kind: 'file', file: upload(latin, 'modelo.html', 'text/html'))

      expect(show(response.parsed_body['id'])['result_mjml']).to include('Chegou a coleção nova')
    end

    it 'refuses a zip bomb' do
      bomb = zip('modelo.html' => html, 'zeros.png' => "\0" * (10.megabytes + 1))
      create_import(source_kind: 'file', file: upload(bomb, 'modelo.zip', 'application/zip'))

      expect(show(response.parsed_body['id'])).to include('status' => 'failed', 'error_code' => 'zip_too_large')
    end

    it 'refuses a zip with a path that climbs out' do
      create_import(source_kind: 'file', file: upload(zip('modelo.html' => html, '../../etc/x.png' => png), 'modelo.zip', 'application/zip'))

      expect(show(response.parsed_body['id'])).to include('status' => 'failed', 'error_code' => 'zip_unsafe_path')
    end

    it 'checks the kind by the bytes and the sizes up front' do
      post path, params: { source_kind: 'file', file: upload("%PDF-1.4\n%\xE2\xE3".b, 'modelo.html', 'text/html') }, headers: headers
      expect(response.parsed_body).to eq('error' => 'email_template_import.unsupported_file')

      post path, params: { source_kind: 'file', file: upload("PK\u0003\u0004#{'x' * 2.megabytes}", 'modelo.zip', 'application/zip') },
                 headers: headers
      expect(response.parsed_body).to eq('error' => 'email_template_import.zip_too_large')

      post path, params: { source_kind: 'file' }, headers: headers
      expect(response.parsed_body).to eq('error' => 'email_template_import.empty')
      expect(EmailCampaignTemplateImport.count).to eq(0)
    end
  end

  describe 'importing by address' do
    it 'refuses anything but https up front' do
      post path, params: { source_kind: 'url', url: 'http://news.example.com/ver' }, headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'email_template_import.url_not_https')
    end

    it 'never reaches a private address' do
      allow(SafeFetch).to receive(:fetch).and_call_original

      create_import(source_kind: 'url', url: 'https://127.0.0.1/modelo.html')

      expect(show(response.parsed_body['id'])).to include('status' => 'failed', 'error_code' => 'url_unsafe')
    end

    it 'imports the page of the address, in the encoding it answered with, with images relative to where it ended up' do
      markup = html.sub('https://cdn.example.com/logo.png', 'img/logo.png').encode(Encoding::Windows_1252).b
      page = EmailCampaigns::Import::UrlSource::Page.new(markup: markup, base_url: 'https://view.news.example.com/c/42/', charset: 'windows-1252')
      allow(EmailCampaigns::Import::UrlSource).to receive(:call).with('https://news.example.com/ver?id=1', deadline: anything).and_return(page)

      create_import(source_kind: 'url', url: 'https://news.example.com/ver?id=1')

      body = show(response.parsed_body['id'])
      expect(body).to include('status' => 'ready', 'source_kind' => 'url')
      expect(body['result_mjml']).to include('Chegou a coleção nova')
      expect(fetched.map(&:first)).to eq(['https://view.news.example.com/c/42/img/logo.png'])
    end
  end

  describe 'one import at a time per account' do
    it 'refuses a second import while the first one holds the lock, and frees it once the lock expires' do
      post path, params: { source_kind: 'paste', content: html }, headers: headers
      first = response.parsed_body['id']

      post path, params: { source_kind: 'paste', content: html }, headers: headers
      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body).to eq('error' => 'email_template_import.in_progress')

      travel 121.seconds do
        post path, params: { source_kind: 'paste', content: html }, headers: headers
        expect(response).to have_http_status(:accepted)
        expect(EmailCampaignTemplateImport.find(first)).to have_attributes(status: 'failed', error_code: 'stalled')
      end
    end

    it 'resumes a dead job when the screen asks for news' do
      post path, params: { source_kind: 'paste', content: html }, headers: headers
      id = response.parsed_body['id']
      EmailCampaignTemplateImport.find(id).claim!
      clear_enqueued_jobs

      travel 121.seconds do
        expect { get "#{path}/#{id}", headers: headers }.to have_enqueued_job(EmailCampaigns::Import::RunJob).with(id)
        expect(response.parsed_body['status']).to eq('queued')
      end
    end
  end

  it 'limits each account to 10 imports every 10 minutes' do
    10.times { EmailCampaignTemplateImport.create!(account: account, source_kind: 'paste', status: 'failed') }

    post path, params: { source_kind: 'paste', content: html }, headers: headers

    expect(response).to have_http_status(:too_many_requests)
    expect(response.parsed_body).to eq('error' => 'email_template_import.rate_limited')
    travel 11.minutes do
      post path, params: { source_kind: 'paste', content: html }, headers: headers
      expect(response).to have_http_status(:accepted)
    end
  end

  describe 'saving in "Meus modelos"' do
    it 'creates the template from the server copy, rechecked, and the images keep working 30 days later' do
      id = paste

      post "#{path}/#{id}/save", params: { name: 'Novidades importadas' }, headers: headers

      expect(response).to have_http_status(:created)
      template = EmailCampaignTemplate.find(response.parsed_body['id'])
      expect(template).to have_attributes(account_id: account.id, category: 'meus-modelos', name: 'Novidades importadas')
      expect(template.body_mjml).to include('Chegou a coleção nova', 'footer-locked')
      expect(EmailCampaignTemplateImport.find(id)).to have_attributes(status: 'saved', email_campaign_template_id: template.id)

      image = Nokogiri::HTML5.fragment(template.body_mjml).at_css('mj-image')['src']
      travel 30.days do
        get URI.parse(image).path
        expect(response).to have_http_status(:found)
      end

      post "#{path}/#{id}/save", params: { name: 'De novo' }, headers: headers
      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body).to eq('error' => 'email_template_import.not_ready')
    end

    it 'blocks the saving while an image did not come or a field is unknown' do
      allow(SafeFetch).to receive(:fetch).and_raise(SafeFetch::HttpError.new('404', status: 404))
      id = paste(html.sub('{{ nome }}', '{{ campo_que_nao_existe }}'))

      expect(show(id)['blocking'].pluck('code')).to contain_exactly('image_missing', 'unknown_fields')

      post "#{path}/#{id}/save", params: { name: 'Com problema' }, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('email_template_import.blocked')
      expect(response.parsed_body['blocking'].pluck('code')).to contain_exactly('image_missing', 'unknown_fields')
      expect(EmailCampaignTemplate.where(account: account).count).to eq(0)
    end

    it 'does not trust an image that is not of this import, even if the stored copy was changed' do
      id = paste
      import = EmailCampaignTemplateImport.find(id)
      import.update!(result_mjml: import.result_mjml.sub('https://app.exemplo.com.br/rails', 'https://evil.example.com/rails'))

      post "#{path}/#{id}/save", params: { name: 'Adulterado' }, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['blocking'].pluck('code')).to include('image_missing')
    end

    it 'copies the custom social icons of an MJML model and never saves an outside one' do
      social = '<mj-social><mj-social-element name="facebook" href="https://f.example.com" src="http://rastreador.example.com/x.png">F' \
               '</mj-social-element></mj-social>'
      id = paste("<mjml><mj-body><mj-section><mj-column><mj-text>Oi</mj-text>#{social}</mj-column></mj-section></mj-body></mjml>")

      body = show(id)
      expect(fetched.map(&:first)).to eq(['https://rastreador.example.com/x.png'])
      expect(body['result_mjml']).not_to include('rastreador')
      expect(body['blocking']).to eq([])

      import = EmailCampaignTemplateImport.find(id)
      icon = Nokogiri::HTML5.fragment(import.result_mjml).at_css('mj-social-element')['src']
      import.update!(result_mjml: import.result_mjml.sub(icon, 'http://rastreador.example.com/x.png'))
      post "#{path}/#{id}/save", params: { name: 'Com rastreador' }, headers: headers
      expect(response.parsed_body['blocking'].pluck('code')).to eq(['image_missing'])
    end

    it 'blocks the saving while a part the converter did not understand is not rebuilt' do
      id = paste('<mjml><mj-body><mj-section><mj-column><mj-text>Oi</mj-text><mj-raw><div>Faltam 3 dias</div></mj-raw>' \
                 '</mj-column></mj-section></mj-body></mjml>')

      expect(show(id)['blocking'].pluck('code')).to eq(['unresolved_parts'])
      post "#{path}/#{id}/save", params: { name: 'Com trecho' }, headers: headers
      expect(response.parsed_body['blocking'].pluck('code')).to eq(['unresolved_parts'])
    end

    it 'answers the progress from what the import stored, without checking the design again' do
      id = paste
      allow(EmailCampaigns::Import::SaveCheck).to receive(:call).and_call_original

      expect(show(id)['blocking']).to eq([])
      expect(EmailCampaigns::Import::SaveCheck).not_to have_received(:call)
    end

    it 'asks for a name that is not taken' do
      EmailCampaignTemplate.create!(account: account, name: 'Já existe', category: 'meus-modelos', body_mjml: '<mjml></mjml>')
      id = paste

      post "#{path}/#{id}/save", params: { name: ' ' }, headers: headers
      expect(response.parsed_body).to eq('error' => 'email_template_import.name_required')
      post "#{path}/#{id}/save", params: { name: 'já existe' }, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'email_template_import.name_taken')
      expect(EmailCampaignTemplateImport.find(id).status).to eq('ready')
    end
  end

  describe 'rebuilding a part with the AI ("Refazer para editar")' do
    let(:raw_model) do
      '<mjml><mj-body><mj-section><mj-column><mj-text>Oi</mj-text><mj-raw><div>Faltam 3 dias</div></mj-raw>' \
        '</mj-column></mj-section></mj-body></mjml>'
    end
    let(:client) { instance_double(Crm::Ai::ResponsesClient) }

    def with_ai
      resolver = instance_double(Crm::Ai::CredentialResolver, configured?: true, resolve: { api_key: 'k', api_base: 'https://ia.example.com' })
      allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(resolver)
      allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
      allow(client).to receive(:create)
        .and_return({ text: { mjml: '<mj-section><mj-column><mj-text>Faltam 3 dias</mj-text></mj-column></mj-section>' }.to_json })
    end

    def rebuild(id, target, auth = headers)
      perform_enqueued_jobs(only: EmailCampaigns::Import::RebuildJob) do
        post "#{path}/#{id}/rebuild", params: { target: target }, headers: auth, as: :json
      end
    end

    it 'rebuilds the part in the background, and the model can be saved' do
      with_ai
      id = paste(raw_model)
      expect(show(id)['ai_rebuild']).to eq('available' => true, 'left' => 5)

      rebuild(id, 'trecho-1')
      expect(response).to have_http_status(:accepted)

      body = show(id)
      expect(body['rebuilds']).to eq('trecho-1' => { 'status' => 'done' })
      expect(body['blocking']).to eq([])
      expect(body['targets']['parts']).to eq([])
      expect(body['result_mjml']).to include('Faltam 3 dias')
      expect(body['ai_rebuild']).to eq('available' => true, 'left' => 4)
      expect(body['fixes'].last).to include('code' => 'unresolved_parts', 'choice' => 'rebuild', 'target' => 'trecho-1')

      rebuild(id, 'trecho-1')
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'email_template_import.fix_gone')

      post "#{path}/#{id}/save", params: { name: 'Refeito' }, headers: headers
      expect(response).to have_http_status(:created)
    end

    it 'says the AI is not configured, and counts nothing' do
      id = paste(raw_model)
      expect(show(id)['ai_rebuild']).to eq('available' => false, 'left' => 0)

      rebuild(id, 'trecho-1')
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'email_template_import.ai_not_configured')
      expect(EmailTemplateImportAiQuota.count).to eq(0)
    end

    it 'is behind the flag, campaign_manage and the account' do
      with_ai
      id = paste(raw_model)
      agent = create(:user, account: account, role: :agent)

      rebuild(id, 'trecho-1', agent.create_new_auth_token)
      expect(response).to have_http_status(:unauthorized)
      foreign = EmailCampaignTemplateImport.create!(account: create(:account), source_kind: 'paste', status: 'ready')
      rebuild(foreign.id, 'trecho-1')
      expect(response).to have_http_status(:not_found)
      account.disable_features!('email_template_import')
      rebuild(id, 'trecho-1')
      expect(response).to have_http_status(:not_found)
      expect(client).not_to have_received(:create)
    end
  end
end
