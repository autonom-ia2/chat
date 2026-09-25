require 'rails_helper'

# #722 — no EE a planilha da Lista é liberada pela chave `crm_export` (crm_admin implica
# todas). Agente sem função não exporta: a chave está em PLAIN_AGENT_DENIED_KEYS.
RSpec.describe 'CRM cards export (Enterprise policy)', type: :request do
  around do |example|
    previous_value = ENV.fetch('CRM_KANBAN_ENABLED', nil)
    ENV['CRM_KANBAN_ENABLED'] = 'true'
    example.run
  ensure
    previous_value.nil? ? ENV.delete('CRM_KANBAN_ENABLED') : ENV['CRM_KANBAN_ENABLED'] = previous_value
  end

  def custom_role_agent(account:, permissions:)
    role = create(:custom_role, account: account, permissions: permissions)
    agent = create(:user)
    create(:account_user, account: account, user: agent, role: :agent, custom_role: role)
    agent
  end

  def exportar(account, user, pipeline)
    get "/api/v1/accounts/#{account.id}/crm/cards/export", params: { pipeline_id: pipeline.id }, headers: auth_headers(user)
  end

  def planilha
    Roo::Excelx.new(StringIO.new(response.body)).sheet(0)
  end

  # Dados a partir da linha seguinte ao cabeçalho (acima dele: título e resumo).
  def primeira = Crm::Cards::XlsxExport::HEADER_ROW + 1

  it 'recusa função sem crm_export, mesmo com crm_view' do
    account, admin = create_account_and_user
    agent = custom_role_agent(account: account, permissions: %w[crm_view crm_manage_cards])
    pipeline, = create_crm_pipeline(account: account, user: admin)

    exportar(account, agent, pipeline)

    expect(response).to have_http_status(:unauthorized)
  end

  # Integração (n8n etc.) não baixa planilha de dado pessoal: a ação fica fora do mapa de
  # escopos do RestrictIntegrationTokenToCrm, que nega por padrão — nem crm_admin passa.
  it 'recusa token de integração, mesmo com crm_admin' do
    account, admin = create_account_and_user
    pipeline, = create_crm_pipeline(account: account, user: admin)
    token = Crm::IntegrationToken.create!(account: account, created_by: admin, name: 'n8n', scopes: ['crm_admin'])

    get "/api/v1/accounts/#{account.id}/crm/cards/export", params: { pipeline_id: pipeline.id },
                                                           headers: { api_access_token: token.access_token.token }

    expect(response).to have_http_status(:unauthorized)
  end

  it 'libera crm_admin, que implica todas as chaves do CRM' do
    account, admin = create_account_and_user
    agent = custom_role_agent(account: account, permissions: %w[crm_admin])
    pipeline, = create_crm_pipeline(account: account, user: admin)

    exportar(account, agent, pipeline)

    expect(response).to have_http_status(:ok)
  end

  it 'com crm_export, traz só os cards e campos que o agente vê' do
    account, admin = create_account_and_user
    agent = custom_role_agent(account: account, permissions: %w[crm_view crm_export])
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    inbox_dele = create_crm_inbox(account: account, name: 'Inbox dele', members: [agent])
    inbox_alheia = create_crm_inbox(account: account, name: 'Inbox alheia')
    contato = account.contacts.create!(name: 'Lead Visível', phone_number: '+5511911112222')
    account.crm_cards.create!(pipeline: pipeline, stage: stage, inbox: inbox_dele, contact: contato, title: 'Card dele')
    account.crm_cards.create!(pipeline: pipeline, stage: stage, inbox: inbox_alheia, title: 'Card de outra inbox')

    exportar(account, agent, pipeline)

    expect(response).to have_http_status(:ok)
    titulos = (primeira..planilha.last_row.to_i).map { |linha| planilha.cell(linha, 1) }
    expect(titulos).to eq(['Card dele'])
  end

  it 'não exporta etiqueta de conversa que o agente não vê' do
    account, admin = create_account_and_user
    agent = custom_role_agent(account: account, permissions: %w[crm_view crm_export])
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    inbox_oculta = create_crm_inbox(account: account, name: 'Inbox oculta')
    contato = account.contacts.create!(name: 'Lead Oculto', phone_number: '+5511933334444')
    conversa = create_crm_conversation(account: account, inbox: inbox_oculta, contact: contato)
    conversa.update!(label_list: ['segredo'])
    account.crm_cards.create!(pipeline: pipeline, stage: stage, owner: agent, primary_conversation: conversa,
                              contact: contato, title: 'Card do agente')

    coluna_etiquetas = Crm::Cards::XlsxExport::COLUMNS.index(:labels) + 1

    # Quem vê a conversa (o administrador) recebe a etiqueta: prova que ela chega na
    # planilha e que é a regra de visibilidade que a tira do agente.
    exportar(account, admin, pipeline)
    expect(planilha.cell(primeira, coluna_etiquetas)).to eq('segredo')

    exportar(account, agent, pipeline)

    expect(response).to have_http_status(:ok)
    expect(planilha.cell(primeira, 1)).to eq('Card do agente')
    expect(planilha.cell(primeira, coluna_etiquetas)).to be_nil
  end
end
