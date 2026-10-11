require 'rails_helper'

# Mexer no card exige o funil dele (#1148, decisão do Rodrigo em 11/10). Quem só vê o card de outro funil (dono ou
# atendente) continua vendo, mas não edita, fecha, arquiva, reabre, move nem vincula. Sem acesso por funil, e para o
# administrador, nada muda.
RSpec.describe 'Acesso por funil: mexer no card', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:vendas_agent) { create_crm_agent(account: account, name: 'Vendas').first }
  let(:inbox) { create_crm_inbox(account: account, members: [vendas_agent]) }
  let(:vendas) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let(:sinistro) { create_crm_pipeline(account: account, user: admin, name: 'Sinistro') }
  let(:contact) { create(:contact, account: account) }
  let(:conversa) { create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: vendas_agent) }
  let(:card_sinistro) do
    account.crm_cards.create!(pipeline: sinistro.first, stage: sinistro.last, title: 'Sinistro', inbox: inbox, contact: contact,
                              primary_conversation: conversa, owner: vendas_agent)
  end
  let(:card_vendas) do
    account.crm_cards.create!(pipeline: vendas.first, stage: vendas.last, title: 'Vendas', inbox: inbox, contact: contact,
                              owner: vendas_agent)
  end

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  def restrict!
    access = Crm::InboxAgentAccess.create!(account: account, inbox: inbox, user: vendas_agent, all_pipelines: false, triage: false)
    access.agent_pipelines.create!(account: account, pipeline: vendas.first)
  end

  def card_url(card, action = nil)
    ["/api/v1/accounts/#{account.id}/crm/cards/#{card.id}", action].compact.join('/')
  end

  def headers(user = vendas_agent)
    user.create_new_auth_token
  end

  def forbidden?
    response.status.in?([401, 403])
  end

  def bulk(card, action, payload = {})
    post "/api/v1/accounts/#{account.id}/crm/cards/bulk",
         params: { ids: [card.id], action_name: action, payload: payload }, headers: headers, as: :json
    response.parsed_body['payload']
  end

  describe 'com acesso por funil' do
    before { restrict! }

    it 'dono e atendente do card de outro funil ainda o veem' do
      get card_url(card_sinistro), headers: headers

      expect(response).to have_http_status(:ok)
    end

    it 'mas não editam, fecham, arquivam nem movem dentro do funil dele' do
      vistoria = create_crm_stage(account: account, pipeline: sinistro.first, name: 'Vistoria')

      patch card_url(card_sinistro), params: { card: { title: 'Outro' } }, headers: headers, as: :json
      expect(forbidden?).to be(true)
      post card_url(card_sinistro, 'close'), params: { result: 'won' }, headers: headers, as: :json
      expect(forbidden?).to be(true)
      delete card_url(card_sinistro), headers: headers, as: :json
      expect(forbidden?).to be(true)
      post card_url(card_sinistro, 'move'), params: { stage_id: vistoria.id }, headers: headers, as: :json
      expect(forbidden?).to be(true)

      expect(card_sinistro.reload).to have_attributes(title: 'Sinistro', status: 'open', stage_id: sinistro.last.id)
    end

    it 'nem vinculam nem desvinculam conversa' do
      outra = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: vendas_agent)

      post card_url(card_sinistro, 'link_conversation'), params: { conversation_id: outra.id }, headers: headers, as: :json
      expect(forbidden?).to be(true)
      post card_url(card_sinistro, 'unlink_conversation'), params: { conversation_id: conversa.id }, headers: headers, as: :json
      expect(forbidden?).to be(true)

      expect(card_sinistro.card_conversations.pluck(:conversation_id)).not_to include(outra.id)
    end

    it 'nem pelo lote (status, arquivar, dono)' do
      expect(bulk(card_sinistro, 'status', result: 'won')['failed']).to contain_exactly({ 'id' => card_sinistro.id, 'error' => 'forbidden' })
      expect(bulk(card_sinistro, 'delete')['failed']).to contain_exactly({ 'id' => card_sinistro.id, 'error' => 'forbidden' })
      expect(bulk(card_sinistro, 'assign', owner_id: admin.id)['failed']).to contain_exactly({ 'id' => card_sinistro.id, 'error' => 'forbidden' })

      expect(card_sinistro.reload).to have_attributes(status: 'open', owner_id: vendas_agent.id)
    end

    it 'no funil dela, mexe normalmente' do
      patch card_url(card_vendas), params: { card: { title: 'Proposta enviada' } }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      post card_url(card_vendas, 'close'), params: { result: 'won' }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(card_vendas.reload).to have_attributes(title: 'Proposta enviada', status: 'won')
    end

    it 'o administrador mexe em qualquer card' do
      patch card_url(card_sinistro), params: { card: { title: 'Revisado' } }, headers: headers(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect(card_sinistro.reload.title).to eq('Revisado')
    end
  end

  describe 'sem nenhuma linha de acesso (todas as contas hoje)' do
    it 'o dono mexe no card de qualquer funil, como antes' do
      patch card_url(card_sinistro), params: { card: { title: 'Outro' } }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      expect(bulk(card_sinistro, 'delete')['updated']).to eq([card_sinistro.id])
      expect(card_sinistro.reload).to have_attributes(title: 'Outro', status: 'archived')
    end
  end
end
