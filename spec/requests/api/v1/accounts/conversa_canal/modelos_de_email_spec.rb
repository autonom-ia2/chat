require 'rails_helper'

# #1786: modelos de e-mail das Campanhas no "+" da resposta. Quem responde a conversa usa, sem permissão de Campanhas.
RSpec.describe 'Modelos de e-mail na resposta' do
  let(:account) { create(:account) }
  let(:inbox) { create(:channel_email, account: account).inbox }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let!(:modelo) { EmailCampaignTemplate.create!(account: account, name: 'Proposta', body_mjml: '<mjml>{{ nome }}</mjml>') }
  let(:base) { "/api/v1/accounts/#{account.id}/conversa_canal/modelos_de_email" }

  before do
    EmailCampaignTemplate.create!(account: nil, name: 'Da galeria', body_html: '<p>g</p>')
    EmailCampaignTemplate.create!(account: create(:account), name: 'De outra conta', body_html: '<p>o</p>')
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, configured?: false))
  end

  it 'sem a chave conversa_email_nova, 404' do
    get base, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end

  context 'with a chave conversa_email_nova ligada' do
    before { account.enable_features!('conversa_email_nova') }

    it 'lista só os modelos salvos da conta, para o atendente comum' do
      get base, headers: agent.create_new_auth_token
      expect(response.parsed_body['payload'].pluck('nome')).to eq(['Proposta'])
    end

    it 'abre o modelo com os campos, se o atendente vê a conversa' do
      create(:inbox_member, user: agent, inbox: inbox)
      get "#{base}/#{modelo.id}", params: { conversation_id: conversation.display_id }, headers: agent.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['campos'].pluck('chave')).to eq(['nome'])
      expect(response.parsed_body['campos'].first['valor']).to eq(conversation.contact.name)
    end

    it 'prévia do modelo, sem campos (miniatura da janela)' do
      get "#{base}/#{modelo.id}/previa", headers: agent.create_new_auth_token
      expect(response.parsed_body).to eq('id' => modelo.id, 'mjml' => '<mjml>{{ nome }}</mjml>', 'html' => nil)
    end

    it 'conversa que o atendente não vê: 401' do
      get "#{base}/#{modelo.id}", params: { conversation_id: conversation.display_id }, headers: agent.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)
    end

    context 'without conversa: pelo contato escolhido (gaveta "Escrever", #1809)' do
      let(:contato) { create(:contact, account: account, name: 'Marina Costa', email: 'marina@exemplo.com.br') }
      let!(:com_campo_sem_fonte) do
        EmailCampaignTemplate.create!(account: account, name: 'Cotação', body_mjml: '<mjml>{{ nome }} {{ numero_da_cotacao }}</mjml>')
      end

      before { create(:inbox_member, user: agent, inbox: inbox) }

      it 'contato da conta: preenche pelo contato, e o campo sem fonte vem vazio sem chamar a IA' do
        get "#{base}/#{com_campo_sem_fonte.id}", params: { contact_id: contato.id, inbox_id: inbox.id }, headers: agent.create_new_auth_token

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['campos']).to eq([
                                                       { 'chave' => 'nome', 'valor' => 'Marina Costa', 'origem' => 'contato' },
                                                       { 'chave' => 'numero_da_cotacao', 'valor' => '', 'origem' => 'vazio' }
                                                     ])
        expect(Crm::Ai::CredentialResolver).not_to have_received(:new)
      end

      it 'mesmo com a IA da conta configurada, não chama a IA (não há conversa para ler)' do
        allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, configured?: true))
        allow(Crm::Ai::ResponsesClient).to receive(:new)

        get "#{base}/#{com_campo_sem_fonte.id}", params: { contact_id: contato.id, inbox_id: inbox.id }, headers: agent.create_new_auth_token

        expect(response.parsed_body['campos'].last).to eq('chave' => 'numero_da_cotacao', 'valor' => '', 'origem' => 'vazio')
        expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
      end

      it 'contato de outra conta: 404' do
        de_fora = create(:contact, account: create(:account))
        get "#{base}/#{modelo.id}", params: { contact_id: de_fora.id, inbox_id: inbox.id }, headers: agent.create_new_auth_token
        expect(response).to have_http_status(:not_found)
      end

      it 'caixa em que o atendente não está: 401 (a mesma checagem de quem cria a conversa)' do
        outra = create(:channel_email, account: account).inbox
        get "#{base}/#{modelo.id}", params: { contact_id: contato.id, inbox_id: outra.id }, headers: agent.create_new_auth_token
        expect(response).to have_http_status(:unauthorized)
      end

      it 'sem conversa nem contato: 422' do
        get "#{base}/#{modelo.id}", headers: agent.create_new_auth_token
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'contato sem a caixa: 422' do
        get "#{base}/#{modelo.id}", params: { contact_id: contato.id }, headers: agent.create_new_auth_token
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
end
