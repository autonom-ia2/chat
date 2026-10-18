require 'rails_helper'

# #1786: ditado da resposta de e-mail (fala vira texto).
RSpec.describe 'Ditado da resposta de e-mail' do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:audio) { Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/sample.ogg'), 'audio/ogg') }
  let(:credencial) { { api_key: 'k', api_base: 'https://api.openai.com/', source: :hook } }

  def ditar(arquivo = audio)
    post "/api/v1/accounts/#{account.id}/conversa_canal/ditados",
         headers: agent.create_new_auth_token, params: { audio: arquivo }
  end

  it 'sem a chave da conta, 404' do
    ditar
    expect(response).to have_http_status(:not_found)
  end

  context 'with a chave conversa_email_nova ligada' do
    before { account.enable_features!('conversa_email_nova') }

    it 'transcreve e devolve o texto, sem deixar o áudio guardado' do
      allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: credencial))
      cliente = instance_double(Crm::Ai::TranscriptionClient, transcribe: ' Oi, Marina, segue a proposta. ')
      allow(Crm::Ai::TranscriptionClient).to receive(:new).and_return(cliente)

      expect { ditar }.not_to change(ActiveStorage::Blob, :count)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['texto']).to eq('Oi, Marina, segue a proposta.')
    end

    it 'o transcritor lê o próprio arquivo recebido, sem subir para o armazenamento' do
      allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: credencial))
      lido = nil
      cliente = instance_double(Crm::Ai::TranscriptionClient)
      allow(cliente).to receive(:transcribe) do |anexo|
        anexo.file.blob.open { |arquivo| lido = arquivo.read.bytesize }
        'ok'
      end
      allow(Crm::Ai::TranscriptionClient).to receive(:new).and_return(cliente)
      allow(ActiveStorage::Blob).to receive(:create_and_upload!)

      ditar

      expect(lido).to eq(File.size(Rails.root.join('spec/assets/sample.ogg')))
      expect(ActiveStorage::Blob).not_to have_received(:create_and_upload!)
    end

    it 'sem IA na conta, explica em português' do
      allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: nil))
      ditar
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(I18n.t('conversa_canal.ditado.sem_ia'))
    end

    it 'arquivo que não é áudio é recusado' do
      allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: credencial))
      ditar(Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/sample.pdf'), 'application/pdf'))
      expect(response.parsed_body['error']).to eq(I18n.t('conversa_canal.ditado.sem_audio'))
    end

    it 'falha do motor vira frase, sem 500' do
      allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: credencial))
      allow(Crm::Ai::TranscriptionClient).to receive(:new).and_raise(Faraday::TimeoutError)
      ditar
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(I18n.t('conversa_canal.ditado.falhou'))
    end

    it 'disponivel diz se a conta tem IA (ditado e tradução)' do
      allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, configured?: true))
      get "/api/v1/accounts/#{account.id}/conversa_canal/ditados/disponivel", headers: agent.create_new_auth_token
      expect(response.parsed_body).to eq('disponivel' => true, 'traducao' => true)
    end

    it 'sem IA, a tradução vale só com o Google Tradutor ligado' do
      allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, configured?: false))
      create(:integrations_hook, account: account, app_id: 'google_translate', settings: { 'project_id' => 'p', 'credentials' => {} })
      get "/api/v1/accounts/#{account.id}/conversa_canal/ditados/disponivel", headers: agent.create_new_auth_token
      expect(response.parsed_body).to eq('disponivel' => false, 'traducao' => true)
    end
  end
end
