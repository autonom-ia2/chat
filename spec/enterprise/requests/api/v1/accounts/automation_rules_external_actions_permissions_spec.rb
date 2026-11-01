require 'rails_helper'

# #2414: webhook e transcrição por e-mail mandam a conversa para fora, como uma integração. Com função personalizada,
# criar, mudar ou copiar uma regra com uma dessas ações pede integration_manage além de automation_manage. Apagar,
# não. A parte de função só existe com o EE carregado.
RSpec.describe 'Regra com webhook e função personalizada', type: :request do
  let(:account) { create(:account) }
  let(:base) { "/api/v1/accounts/#{account.id}/automation_rules" }
  let(:webhook) { [{ action_name: 'send_webhook_event', action_params: ['https://example.com/hook'] }] }
  let(:etiqueta) { [{ action_name: 'add_label', action_params: ['lead'] }] }
  let(:condicoes) { [{ attribute_key: 'status', filter_operator: 'equal_to', values: ['open'], query_operator: nil }] }
  let(:regra_com_webhook) do
    create(:automation_rule, account: account, event_name: 'conversation_created', conditions: condicoes, actions: webhook)
  end
  let(:so_automacao) { custom_role_user('automation_manage') }
  let(:automacao_e_integracao) { custom_role_user('automation_manage', 'integration_manage') }

  def custom_role_user(*permissions)
    user = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: permissions)
    user.account_users.find_by(account: account).update!(custom_role: role)
    user
  end

  def criar(user, actions)
    post base, params: { name: 'Avisa o sistema', event_name: 'conversation_created', conditions: condicoes, actions: actions },
               headers: user.create_new_auth_token, as: :json
  end

  it 'só com automation_manage, não cria regra com webhook' do
    expect { criar(so_automacao, webhook) }.not_to change(AutomationRule, :count)
    expect(response).to have_http_status(:unauthorized)
  end

  it 'só com automation_manage, não cria regra com transcrição por e-mail' do
    criar(so_automacao, [{ action_name: 'send_email_transcript', action_params: ['time@example.com'] }])

    expect(response).to have_http_status(:unauthorized)
  end

  it 'só com automation_manage, cria regra sem ação que sai da plataforma' do
    criar(so_automacao, etiqueta)

    expect(response).to have_http_status(:ok)
  end

  it 'com integration_manage, cria regra com webhook' do
    criar(automacao_e_integracao, webhook)

    expect(response).to have_http_status(:ok)
  end

  it 'só com automation_manage, não muda nem liga a regra que já tem webhook' do
    patch "#{base}/#{regra_com_webhook.id}", params: { active: false }, headers: so_automacao.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(regra_com_webhook.reload.active).to be(true)
  end

  it 'só com automation_manage, não liga a regra desligada que tem webhook' do
    regra_com_webhook.update!(active: false)

    patch "#{base}/#{regra_com_webhook.id}", params: { active: true }, headers: so_automacao.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(regra_com_webhook.reload.active).to be(false)
  end

  it 'só com automation_manage, actions nulo não fura a checagem' do
    patch "#{base}/#{regra_com_webhook.id}", params: { active: false, actions: nil }, headers: so_automacao.create_new_auth_token,
                                             as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(regra_com_webhook.reload.active).to be(true)
  end

  it 'só com automation_manage, não tira o webhook da regra (actions vazio ou trocado)' do
    [[], etiqueta].each do |actions|
      patch "#{base}/#{regra_com_webhook.id}", params: { actions: actions }, headers: so_automacao.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
    expect(regra_com_webhook.reload.actions.first['action_name']).to eq('send_webhook_event')
  end

  it 'só com automation_manage, webhook mandado como formulário também é recusado' do
    post base, params: { name: 'Avisa o sistema', event_name: 'conversation_created',
                         conditions: { '0' => condicoes.first }, actions: { '0' => webhook.first } },
               headers: so_automacao.create_new_auth_token

    expect(response).to have_http_status(:unauthorized)
    expect(AutomationRule.count).to eq(0)
  end

  it 'só com automation_manage, não troca a ação por um webhook' do
    regra = create(:automation_rule, account: account, event_name: 'conversation_created', conditions: condicoes, actions: etiqueta)

    patch "#{base}/#{regra.id}", params: { actions: webhook }, headers: so_automacao.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  it 'só com automation_manage, não copia a regra que tem webhook' do
    origem = regra_com_webhook
    token = so_automacao.create_new_auth_token

    expect { post "#{base}/#{origem.id}/clone", headers: token, as: :json }.not_to change(AutomationRule, :count)
    expect(response).to have_http_status(:unauthorized)
  end

  it 'só com automation_manage, apaga a regra que tem webhook' do
    delete "#{base}/#{regra_com_webhook.id}", headers: so_automacao.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
  end

  it 'com integration_manage, muda a regra que tem webhook' do
    patch "#{base}/#{regra_com_webhook.id}", params: { active: false }, headers: automacao_e_integracao.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(regra_com_webhook.reload.active).to be(false)
  end

  it 'o administrador copia a regra que tem webhook' do
    origem = regra_com_webhook
    token = create(:user, account: account, role: :administrator).create_new_auth_token

    expect { post "#{base}/#{origem.id}/clone", headers: token, as: :json }.to change(AutomationRule, :count).by(1)
  end

  it 'o administrador cria regra com webhook' do
    criar(create(:user, account: account, role: :administrator), webhook)

    expect(response).to have_http_status(:ok)
  end
end
