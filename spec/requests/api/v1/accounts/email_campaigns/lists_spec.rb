require 'rails_helper'

# G52 (#2760): as listas de e-mail da conta e a campanha de e-mail com a lista como público.
RSpec.describe 'Email lists', :aggregate_failures, type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/email_campaigns" }

  around do |example|
    with_modified_env(CRM_KANBAN_ENABLED: 'true', EMAIL_CAMPAIGN_ENABLED: 'true', EMAIL_CAMPAIGN_HYGIENE_MODE: 'shadow',
                      EMAIL_REPUTATION_MODE: 'shadow', EMAIL_REPUTATION_PROVIDER_MONITOR: 'false',
                      EMAIL_REPUTATION_PROVIDER_BLOCK: 'false', EMAIL_REPUTATION_AWS_ACCOUNT_ID: '') { example.run }
  end

  before { allow(EmailCampaigns::RecipientPreflightJob).to receive(:enqueue) }

  describe 'listas' do
    it 'cria, lista com quantos estão e quantos recebem, renomeia e apaga sem tirar a etiqueta' do
      post "#{base}/lists", params: { email_list: { name: 'Dicas do mês' } }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:created)
      lista = EmailList.find(response.parsed_body['id'])
      create(:contact, account: account, email: 'ana@exemplo.com').update_labels([lista.label.title])
      create(:contact, account: account, email: nil, phone_number: '+5511988887777').update_labels([lista.label.title])

      get "#{base}/lists", headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body).to eq([{ 'id' => lista.id, 'name' => 'Dicas do mês', 'label_id' => lista.label_id,
                                            'contatos_count' => 2, 'recebem_count' => 1 }])

      patch "#{base}/lists/#{lista.id}", params: { email_list: { name: 'Novidades' } }, headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['name']).to eq('Novidades')
      expect(lista.reload.label.title).to eq('lista-email-dicas-do-mes')

      delete "#{base}/lists/#{lista.id}", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:no_content)
      expect(Label.exists?(lista.label_id)).to be(true)
    end

    it 'diz o erro do nome repetido' do
      EmailList.criar(account: account, name: 'Dicas do mês')

      post "#{base}/lists", params: { email_list: { name: 'Dicas do mês' } }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'email_list.invalid', 'errors' => { 'name' => ['taken'] })
    end

    it 'o pedido que perde a corrida pelo mesmo nome recebe nome repetido, não 500' do
      allow(EmailList).to receive(:titulo_livre).and_raise(ActiveRecord::RecordNotUnique)

      post "#{base}/lists", params: { email_list: { name: 'Dicas do mês' } }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'email_list.invalid', 'errors' => { 'name' => ['taken'] })
    end

    it 'não apaga lista usada por campanha agendada' do
      lista = EmailList.criar(account: account, name: 'Dicas do mês')
      create(:email_campaign, account: account).update_columns(email_list_id: lista.id, status: EmailCampaign.statuses[:scheduled]) # rubocop:disable Rails/SkipsModelValidations

      delete "#{base}/lists/#{lista.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('email_list.in_use')
    end

    it 'apaga a lista sob a trava de envio de cada campanha que a usa, e o rascunho fica sem os pendentes dela' do
      lista = EmailList.criar(account: account, name: 'Dicas do mês')
      create(:contact, account: account, email: 'ana@exemplo.com').update_labels([lista.label.title])
      rascunho = create(:email_campaign, account: account)
      rascunho.update!(email_list: lista)
      allow(EmailCampaigns::Reputation::Admission).to receive(:new).and_call_original

      delete "#{base}/lists/#{lista.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:no_content)
      expect(EmailCampaigns::Reputation::Admission).to have_received(:new).with(having_attributes(id: rascunho.id)).at_least(:once)
      expect(rascunho.reload.email_list_id).to be_nil
      expect(rascunho.email_campaign_recipients.count).to eq(0)
    end

    it 'não mostra nem mexe na lista de outra conta' do
      outra = EmailList.criar(account: create(:account), name: 'Outra')

      get "#{base}/lists", headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body).to be_empty
      patch "#{base}/lists/#{outra.id}", params: { email_list: { name: 'X' } }, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
      delete "#{base}/lists/#{outra.id}", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
      expect(EmailList.exists?(outra.id)).to be(true)
    end

    it 'conta cada lista à parte, sem somar contato de outra lista nem de outra conta' do
      dicas = EmailList.criar(account: account, name: 'Dicas do mês')
      saudade = EmailList.criar(account: account, name: 'Saudade')
      fora = EmailList.criar(account: create(:account), name: 'Dicas do mês')
      create(:contact, account: account, email: 'ana@exemplo.com').update_labels([dicas.label.title, saudade.label.title])
      create(:contact, account: account, email: 'bia@exemplo.com').tap { |bia| bia.update_labels([dicas.label.title]) }.opt_out!(source: 'manual')
      create(:contact, account: fora.account, email: 'caio@exemplo.com').update_labels([fora.label.title])

      get "#{base}/lists", headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body.map { |lista| lista.values_at('name', 'contatos_count', 'recebem_count') })
        .to eq([['Dicas do mês', 2, 1], ['Saudade', 1, 1]])
    end

    it 'a etiqueta de uma lista em uso não sai pela tela de etiquetas; a de lista livre sai e leva a lista' do
      lista = EmailList.criar(account: account, name: 'Dicas do mês')
      campanha = create(:email_campaign, account: account)
      campanha.update_columns(email_list_id: lista.id) # rubocop:disable Rails/SkipsModelValidations
      allow(EmailCampaigns::Reputation::Admission).to receive(:new).and_call_original

      EmailList::CAMPANHAS_EM_USO.each do |status|
        campanha.update_columns(status: EmailCampaign.statuses[status]) # rubocop:disable Rails/SkipsModelValidations
        delete "/api/v1/accounts/#{account.id}/labels/#{lista.label_id}", headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body).to eq('error' => 'email_list.in_use', 'message' => I18n.t('email_lists.label_in_use'))
        expect(Label.exists?(lista.label_id)).to be(true)
      end

      campanha.update_columns(status: EmailCampaign.statuses[:draft]) # rubocop:disable Rails/SkipsModelValidations
      delete "/api/v1/accounts/#{account.id}/labels/#{lista.label_id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(EmailCampaigns::Reputation::Admission).to have_received(:new).with(having_attributes(id: campanha.id)).at_least(:once)
      expect(EmailList.exists?(lista.id)).to be(false)
      expect(campanha.reload.email_list_id).to be_nil
    end

    it 'etiqueta comum continua saindo pela tela de etiquetas' do
      etiqueta = create(:label, account: account, title: 'vip')

      delete "/api/v1/accounts/#{account.id}/labels/#{etiqueta.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(Label.exists?(etiqueta.id)).to be(false)
    end

    it 'a etiqueta da lista não troca de título pela tela de etiquetas' do
      lista = EmailList.criar(account: account, name: 'Dicas do mês')

      patch "/api/v1/accounts/#{account.id}/labels/#{lista.label_id}",
            params: { label: { title: 'outra' } }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(lista.label.reload.title).to eq('lista-email-dicas-do-mes')
    end

    it 'no OSS, o agente não vê nem cria lista (campaign_view e campaign_manage são do administrador)' do
      get "#{base}/lists", headers: agente.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
      post "#{base}/lists", params: { email_list: { name: 'X' } }, headers: agente.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'com as campanhas de e-mail desligadas, responde desligado' do
      with_modified_env(EMAIL_CAMPAIGN_ENABLED: 'false') { get "#{base}/lists", headers: admin.create_new_auth_token, as: :json }

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body['error']).to eq('email_campaign.disabled')
    end
  end

  describe 'campanha com lista' do
    let(:lista) { EmailList.criar(account: account, name: 'Dicas do mês') }
    let(:campanha) { create(:email_campaign, account: account, status: :draft) }

    before { create(:contact, account: account, email: 'ana@exemplo.com').update_labels([lista.label.title]) }

    it 'escolher a lista no rascunho monta os destinatários e devolve a lista' do
      patch "#{base}/campaigns/#{campanha.id}", params: { email_campaign: { email_list_id: lista.id } },
                                                headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['payload']).to include('email_list_id' => lista.id, 'email_list_name' => 'Dicas do mês', 'recipients_count' => 1)
    end

    it 'duplicar copia a lista' do
      campanha.update!(email_list: lista)

      post "#{base}/campaigns/#{campanha.id}/duplicate", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:created)
      copia = EmailCampaign.find(response.parsed_body.dig('payload', 'id'))
      expect(copia.email_list_id).to eq(lista.id)
      expect(copia.email_campaign_recipients.pluck(:email)).to eq(%w[ana@exemplo.com])
    end

    it 'não aceita planilha' do
      campanha.update!(email_list: lista)
      upload = Rack::Test::UploadedFile.new(StringIO.new("Email\nx@exemplo.com\n"), 'text/csv', original_filename: 'r.csv')

      post "#{base}/campaigns/#{campanha.id}/recipients", params: { import_file: upload }, headers: admin.create_new_auth_token
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('email_campaign.email_list_linked')
      post "#{base}/campaigns/#{campanha.id}/recipients/retry_import", headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['error']).to eq('email_campaign.email_list_linked')
    end

    it 'não aceita lista de outra conta' do
      outra = EmailList.criar(account: create(:account), name: 'Outra')

      patch "#{base}/campaigns/#{campanha.id}", params: { email_campaign: { email_list_id: outra.id } },
                                                headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(campanha.reload.email_list_id).to be_nil
    end
  end
end
