require 'rails_helper'

# Filtro "Funil" (multifunil #1150): a lista aceita crm_pipeline_id e cada conversa traz os funis dela
# (crm_pipeline_ids), lidos da API, para o painel conferir a conversa que chega ou muda.
RSpec.describe 'Conversations API: filtro Funil', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create_crm_agent(account: account, name: 'Vendas').first }
  let(:inbox) { create_crm_inbox(account: account, members: [agent]) }
  let(:vendas) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let(:sinistro) { create_crm_pipeline(account: account, user: admin, name: 'Sinistro') }
  let!(:conversa_vendas) { conversation.tap { |conversa| card(conversa, vendas) } }
  let!(:conversa_sinistro) { conversation.tap { |conversa| card(conversa, sinistro) } }
  let!(:triagem) { conversation }

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  def conversation
    contact = account.contacts.create!(name: "Lead #{SecureRandom.hex(3)}", phone_number: "+55119#{rand(10_000_000..99_999_999)}")
    create_crm_conversation(account: account, inbox: inbox, contact: contact)
  end

  def card(conversa, (pipeline, stage))
    account.crm_cards.create!(pipeline: pipeline, stage: stage, title: pipeline.name, inbox: inbox, contact: conversa.contact,
                              primary_conversation: conversa)
  end

  def list(**params)
    get "/api/v1/accounts/#{account.id}/conversations", headers: agent.create_new_auth_token,
                                                        params: { assignee_type: 'all' }.merge(params)
    expect(response).to have_http_status(:success)
    response.parsed_body['data']
  end

  it 'cada conversa traz os funis dela; sem card, lista vazia' do
    payload = list['payload'].to_h { |conversa| [conversa['id'], conversa['crm_pipeline_ids']] }

    expect(payload).to eq(conversa_vendas.display_id => [vendas.first.id], conversa_sinistro.display_id => [sinistro.first.id],
                          triagem.display_id => [])
  end

  it 'crm_pipeline_id filtra a lista e a contagem' do
    data = list(crm_pipeline_id: sinistro.first.id)

    expect(data['payload'].pluck('id')).to eq([conversa_sinistro.display_id])
    expect(data['meta']['all_count']).to eq(1)
  end

  it 'o meta da lista conta com o mesmo filtro' do
    get "/api/v1/accounts/#{account.id}/conversations/meta", headers: agent.create_new_auth_token,
                                                             params: { assignee_type: 'all', crm_pipeline_id: 'none' }

    expect(response.parsed_body['meta']['all_count']).to eq(1)
  end

  it 'agente restrito não recebe o id do funil oculto: a conversa dele vem com crm_pipeline_hidden' do
    access = Crm::InboxAgentAccess.create!(account: account, inbox: inbox, user: agent, all_pipelines: false, triage: true)
    access.agent_pipelines.create!(account: account, pipeline: vendas.first)
    conversa_sinistro.update!(assignee: agent)

    conversa = list['payload'].find { |item| item['id'] == conversa_sinistro.display_id }

    expect(conversa['crm_pipeline_ids']).to eq([])
    expect(conversa['crm_pipeline_hidden']).to be(true)
    expect(response.body).not_to include(%("crm_pipeline_ids":[#{sinistro.first.id}]))
  end

  it 'o websocket e o webhook não levam os funis: o payload também chega ao contato pelo widget' do
    expect(conversa_vendas.push_event_data).not_to have_key(:crm_pipeline_ids)
    expect(conversa_vendas.webhook_data).not_to have_key(:crm_pipeline_ids)
  end

  it 'a conversa lida sozinha (show) traz os funis dela' do
    get "/api/v1/accounts/#{account.id}/conversations/#{conversa_vendas.display_id}", headers: agent.create_new_auth_token

    expect(response.parsed_body['crm_pipeline_ids']).to eq([vendas.first.id])
  end

  it 'as conversas do contato também trazem os funis' do
    get "/api/v1/accounts/#{account.id}/contacts/#{conversa_sinistro.contact_id}/conversations", headers: agent.create_new_auth_token

    expect(response.parsed_body['payload'].pluck('crm_pipeline_ids')).to eq([[sinistro.first.id]])
  end
end
