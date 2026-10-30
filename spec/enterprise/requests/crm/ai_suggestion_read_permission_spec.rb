require 'rails_helper'

# Sugestão de etapa da IA (#2150, decisão do Rodrigo em 23/10): só quem tem `crm_manage_ai` lê. Sem a chave, o card do
# quadro sai sem ai_suggestion, o filtro "Pendente de IA" é ignorado (revelaria quais cards têm sugestão) e o
# current_ai_suggestion recusa. Segue CrmPermissions#crm_permission?: administrador lê, agente sem função não
# (crm_manage_ai está em PLAIN_AGENT_DENIED_KEYS), função só com crm_manage_ai ou crm_admin.
RSpec.describe 'Quem lê a sugestão de etapa da IA (#2150)', :aggregate_failures, type: :request do
  around do |example|
    with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true') { example.run }
  end

  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:admin) { account_and_user.last }
  let(:so_ver) { pessoa_com(%w[crm_view crm_manage_cards contact_view]) }
  let(:com_ia) { pessoa_com(%w[crm_view crm_manage_ai contact_view]) }
  let(:crm_admin) { pessoa_com(%w[crm_admin contact_view]) }
  let(:plain_agent) { create_crm_agent(account: account).first }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:pipeline) { pipeline_and_stage.first }
  let(:stage) { pipeline_and_stage.last }
  let(:inbox) { create_crm_inbox(account: account, members: [so_ver, com_ia, crm_admin, plain_agent]) }
  let(:contato) { account.contacts.create!(name: 'Cliente', phone_number: '+5511955557777') }
  let!(:com_sugestao) { criar_card('Com sugestão') }
  let!(:sugestao) do
    proposta = create_crm_stage(account: account, pipeline: pipeline, name: 'Proposta')
    Crm::Ai::SuggestionRecorder.new(card: com_sugestao, from_stage: stage, to_stage: proposta, confidence: 0.8,
                                    reasoning: 'Pediu proposta.', model_used: 'm', status: :pending).perform
  end

  before { criar_card('Sem sugestão') }

  def crm = "/api/v1/accounts/#{account.id}/crm"

  def pessoa_com(permissions)
    user = create(:user, account: account, role: :agent)
    role = CustomRole.create!(account: account, name: "Cargo #{SecureRandom.hex(4)}", permissions: permissions)
    AccountUser.find_by(account: account, user: user).update!(custom_role: role)
    user
  end

  def criar_card(titulo)
    account.crm_cards.create!(pipeline: pipeline, stage: stage, inbox: inbox, contact: contato, owner: admin, title: titulo)
  end

  def ler(path, user, params = {})
    get "#{crm}/#{path}", params: params, headers: auth_headers(user)
    expect(response).to have_http_status(:ok)
    response.parsed_body['payload']
  end

  def cards_do_quadro(user, params = {})
    colunas = ler('kanban', user, { pipeline_id: pipeline.id }.merge(params))['stages']
    colunas.flat_map { |coluna| coluna['cards'] }.index_by { |card| card['title'] }
  end

  def titulos_da_lista(user, params = {})
    ler('cards', user, { pipeline_id: pipeline.id }.merge(params)).pluck('title')
  end

  def eventos_do_historico(user)
    ler("cards/#{com_sugestao.id}", user)['activities'].pluck('event_type')
  end

  def sugestao_atual(user)
    get "#{crm}/cards/#{com_sugestao.id}/current_ai_suggestion", headers: auth_headers(user)
  end

  describe 'sem crm_manage_ai (função só com crm_view, agente sem função)' do
    it 'o quadro não traz a sugestão' do
      [so_ver, plain_agent].each do |user|
        cards = cards_do_quadro(user)
        expect(cards.keys).to contain_exactly('Com sugestão', 'Sem sugestão')
        expect(cards['Com sugestão']).not_to have_key('ai_suggestion')
      end
    end

    it 'o filtro "Pendente de IA" é ignorado no quadro e na lista, sem erro' do
      [so_ver, plain_agent].each do |user|
        expect(cards_do_quadro(user, ai_pending: true).keys).to contain_exactly('Com sugestão', 'Sem sugestão')
        expect(titulos_da_lista(user, ai_pending: true)).to contain_exactly('Com sugestão', 'Sem sugestão')
      end
    end

    it 'o histórico do card não traz a sugestão (etapa sugerida e confiança)' do
      [so_ver, plain_agent].each do |user|
        expect(eventos_do_historico(user)).not_to include('ai_suggested')
      end
    end

    it 'current_ai_suggestion recusa como as outras recusas do CRM' do
      [so_ver, plain_agent].each do |user|
        sugestao_atual(user)
        expect(response).to have_http_status(:unauthorized)
        expect(response.body).not_to include('Pediu proposta.')
      end
    end
  end

  describe 'com crm_manage_ai, crm_admin ou administrador' do
    it 'o quadro traz a sugestão' do
      [com_ia, crm_admin, admin].each do |user|
        expect(cards_do_quadro(user)['Com sugestão']['ai_suggestion']).to include('id' => sugestao.id, 'to_stage_name' => 'Proposta')
      end
    end

    it 'o filtro "Pendente de IA" vale no quadro e na lista' do
      [com_ia, crm_admin, admin].each do |user|
        expect(cards_do_quadro(user, ai_pending: true).keys).to eq(['Com sugestão'])
        expect(titulos_da_lista(user, ai_pending: true)).to eq(['Com sugestão'])
      end
    end

    it 'o histórico do card traz a sugestão' do
      [com_ia, crm_admin, admin].each do |user|
        expect(eventos_do_historico(user)).to include('ai_suggested')
      end
    end

    it 'current_ai_suggestion devolve a sugestão' do
      [com_ia, crm_admin, admin].each do |user|
        expect(ler("cards/#{com_sugestao.id}/current_ai_suggestion", user)).to include('id' => sugestao.id, 'reasoning' => 'Pediu proposta.')
      end
    end
  end
end
