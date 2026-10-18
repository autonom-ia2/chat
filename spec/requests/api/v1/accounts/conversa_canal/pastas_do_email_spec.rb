require 'rails_helper'

# #1809: mover a conversa de e-mail para Spam ou Lixeira pelo painel.
RSpec.describe 'Pastas do e-mail' do
  let(:account) { create(:account) }
  let(:inbox) { create(:channel_email, account: account).inbox }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:conversa) { create(:conversation, account: account, inbox: inbox) }
  let(:caminho) { "/api/v1/accounts/#{account.id}/conversa_canal/pastas_do_email/#{conversa.display_id}" }

  it 'sem a chave conversa_email_nova, 404' do
    get caminho, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end

  context 'with a chave conversa_email_nova ligada' do
    before { account.enable_features!('conversa_email_nova') }

    it 'o atendente da caixa move para a Lixeira e lê a pasta' do
      create(:inbox_member, user: agent, inbox: inbox)
      put caminho, params: { pasta: 'lixeira' }, headers: agent.create_new_auth_token
      expect(response.parsed_body).to eq('pasta' => 'lixeira')

      get caminho, headers: agent.create_new_auth_token
      expect(response.parsed_body).to eq('pasta' => 'lixeira')
    end

    it 'quem não vê a conversa: 401' do
      put caminho, params: { pasta: 'spam' }, headers: agent.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
