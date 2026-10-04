require 'rails_helper'

# #859 — quem tem a função "Automações: Ver" testa a regra (o ensaio só lê); quem não tem
# nenhuma chave de automação fica de fora. A parte de função só existe com o EE carregado.
RSpec.describe 'Ensaio de automação com função personalizada', type: :request do
  let(:account) { create(:account) }
  let(:rule) { create(:automation_rule, account: account, event_name: 'conversation_created') }

  def custom_role_user(*permissions)
    user = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: permissions)
    user.account_users.find_by(account: account).update!(custom_role: role)
    user
  end

  def ensaiar(user)
    post "/api/v1/accounts/#{account.id}/automation_rules/#{rule.id}/ensaio",
         headers: user.create_new_auth_token, as: :json
  end

  it 'deixa testar quem tem automation_view' do
    ensaiar(custom_role_user('automation_view'))

    expect(response).to have_http_status(:ok)
  end

  it 'deixa testar quem tem automation_manage' do
    ensaiar(custom_role_user('automation_manage'))

    expect(response).to have_http_status(:ok)
  end

  it 'recusa função sem chave de automação' do
    ensaiar(custom_role_user('label_manage'))

    expect(response).to have_http_status(:unauthorized)
  end
end
