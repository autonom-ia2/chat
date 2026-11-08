require 'rails_helper'

# #2414 F1.3 (D4): com a flag `automacao_fundacao`, a regra que mexe no funil (cria, move, ganha, perde ou atribui card,
# ou depende do funil nas condições) pede também crm_manage_pipelines ou crm_admin, além de automation_manage. É o
# espelho da automação de etapa, que pede as duas. Sem a flag, como antes. A parte de função só existe com o EE.
RSpec.describe 'Regra que mexe no funil e função personalizada', type: :request do
  let(:account) { create(:account) }
  let(:base) { "/api/v1/accounts/#{account.id}/automation_rules" }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:etapa) { create_crm_pipeline(account: account, user: admin).last }
  let(:mover) { [{ action_name: 'crm_move_card_stage', action_params: [etapa.id] }] }
  let(:etiqueta) { [{ action_name: 'add_label', action_params: ['lead'] }] }
  let(:aberta) { [{ attribute_key: 'status', filter_operator: 'equal_to', values: ['open'], query_operator: nil }] }
  let(:no_funil) { [{ attribute_key: 'crm_card_status', filter_operator: 'equal_to', values: ['open'], query_operator: nil }] }
  let(:so_automacao) { custom_role_user('automation_manage') }

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  before { account.enable_features!('automacao_fundacao') }

  def custom_role_user(*permissions)
    user = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: permissions)
    user.account_users.find_by(account: account).update!(custom_role: role)
    user
  end

  def criar(user, actions, conditions = aberta)
    post base, params: { name: 'Lead no funil', event_name: 'conversation_created', conditions: conditions, actions: actions },
               headers: user.create_new_auth_token, as: :json
  end

  it 'só com automation_manage, não cria regra que move card' do
    expect { criar(so_automacao, mover) }.not_to change(AutomationRule, :count)
    expect(response).to have_http_status(:unauthorized)
  end

  it 'só com automation_manage, não cria regra que cria card' do
    criar(so_automacao, [{ action_name: 'crm_create_card', action_params: [etapa.id] }])

    expect(response).to have_http_status(:unauthorized)
  end

  it 'só com automation_manage, não cria regra que depende do funil nas condições' do
    criar(so_automacao, etiqueta, no_funil)

    expect(response).to have_http_status(:unauthorized)
  end

  it 'só com automation_manage, cria regra que não mexe no funil' do
    criar(so_automacao, etiqueta)

    expect(response).to have_http_status(:ok)
  end

  it 'com crm_manage_pipelines ou crm_admin, cria regra que move card' do
    %w[crm_manage_pipelines crm_admin].each do |chave|
      criar(custom_role_user('automation_manage', chave), mover)

      expect(response).to have_http_status(:ok)
    end
  end

  it 'só com automation_manage, não muda nem copia a regra que já move card' do
    regra = create(:automation_rule, account: account, event_name: 'conversation_created', conditions: aberta, actions: mover)

    patch "#{base}/#{regra.id}", params: { active: false }, headers: so_automacao.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(regra.reload.active).to be(true)

    expect { post "#{base}/#{regra.id}/clone", headers: so_automacao.create_new_auth_token, as: :json }
      .not_to change(AutomationRule, :count)
    expect(response).to have_http_status(:unauthorized)
  end

  it 'só com automation_manage, apaga a regra que move card' do
    regra = create(:automation_rule, account: account, event_name: 'conversation_created', conditions: aberta, actions: mover)

    delete "#{base}/#{regra.id}", headers: so_automacao.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
  end

  it 'sem a flag, só com automation_manage, cria regra que move card como antes' do
    account.disable_features!('automacao_fundacao')

    criar(so_automacao, mover)

    expect(response).to have_http_status(:ok)
  end
end
