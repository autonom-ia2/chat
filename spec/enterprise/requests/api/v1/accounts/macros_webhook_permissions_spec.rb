require 'rails_helper'

# #2451: a macro com webhook manda a conversa para fora, como a regra automática (#2448). Quem não é administrador
# precisa de integration_manage para criar ou mudar uma macro que tem ou vai ter webhook. A parte de função só existe
# com o EE carregado.
RSpec.describe 'Macro com webhook e função personalizada', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:base) { "/api/v1/accounts/#{account.id}/macros" }
  let(:webhook) { [{ action_name: 'send_webhook_event', action_params: ['https://hooks.exemplo.com/macro'] }] }
  let(:etiqueta) { [{ action_name: 'add_label', action_params: ['lead'] }] }
  let(:so_macros) { custom_role_user('macro_manage') }
  let(:macros_e_integracao) { custom_role_user('macro_manage', 'integration_manage') }
  let(:macro_com_webhook) do
    create(:macro, account: account, visibility: :global, created_by: admin, updated_by: admin,
                   actions: [{ 'action_name' => 'send_webhook_event', 'action_params' => ['https://hooks.exemplo.com/macro'] }])
  end

  def custom_role_user(*permissions)
    user = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: permissions)
    user.account_users.find_by(account: account).update!(custom_role: role)
    user
  end

  def criar(user, actions)
    post base, params: { name: 'Avisa o sistema', visibility: 'global', actions: actions }, headers: user.create_new_auth_token, as: :json
  end

  it 'só com macro_manage, não cria macro com webhook' do
    expect { criar(so_macros, webhook) }.not_to change(Macro, :count)
    expect(response).to have_http_status(:unauthorized)
  end

  it 'só com macro_manage, cria macro sem webhook' do
    criar(so_macros, etiqueta)

    expect(response).to have_http_status(:ok)
  end

  it 'com integration_manage, cria macro com webhook' do
    criar(macros_e_integracao, webhook)

    expect(response).to have_http_status(:ok)
  end

  it 'o administrador cria macro com webhook' do
    criar(admin, webhook)

    expect(response).to have_http_status(:ok)
  end

  it 'só com macro_manage, não muda a macro que já tem webhook, nem só o nome', :aggregate_failures do
    patch "#{base}/#{macro_com_webhook.id}", params: { name: 'Outro nome' }, headers: so_macros.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(macro_com_webhook.reload.name).not_to eq('Outro nome')
  end

  it 'só com macro_manage, tirar o webhook da macro também é mexer na integração', :aggregate_failures do
    patch "#{base}/#{macro_com_webhook.id}", params: { actions: etiqueta }, headers: so_macros.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(macro_com_webhook.reload.actions.pluck('action_name')).to eq(['send_webhook_event'])
  end

  it 'só com macro_manage, não põe webhook numa macro que não tinha' do
    macro = create(:macro, account: account, visibility: :global, created_by: admin, updated_by: admin)

    patch "#{base}/#{macro.id}", params: { actions: webhook }, headers: so_macros.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  it 'com integration_manage, muda a macro com webhook' do
    patch "#{base}/#{macro_com_webhook.id}", params: { name: 'Outro nome' }, headers: macros_e_integracao.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
  end

  it 'só com macro_manage, apaga a macro com webhook (apagar não pede a chave)' do
    delete "#{base}/#{macro_com_webhook.id}", headers: so_macros.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
  end
end
