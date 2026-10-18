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

    it 'conversa que o atendente não vê: 401' do
      get "#{base}/#{modelo.id}", params: { conversation_id: conversation.display_id }, headers: agent.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
