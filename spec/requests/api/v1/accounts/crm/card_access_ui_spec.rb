require 'rails_helper'

# Acesso por funil na tela do card (#1149): quem não pode ser dono, se a pessoa pode mexer no card e a recusa com
# código próprio. Sem acesso por funil na conta, nada muda.
RSpec.describe 'Acesso por funil: o que a tela do card precisa saber', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:vendas_agent) { create_crm_agent(account: account, name: 'Vendas').first }
  let(:sinistro_agent) { create_crm_agent(account: account, name: 'Sinistro').first }
  let(:inbox) { create_crm_inbox(account: account, members: [vendas_agent, sinistro_agent]) }
  let(:vendas) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let(:sinistro) { create_crm_pipeline(account: account, user: admin, name: 'Sinistro') }
  let(:card) do
    account.crm_cards.create!(pipeline: vendas.first, stage: vendas.last, title: 'Vendas', inbox: inbox, owner: vendas_agent,
                              contact: create(:contact, account: account))
  end
  let(:base) { "/api/v1/accounts/#{account.id}/crm/cards" }

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  def restrict(user, (pipeline, _stage))
    access = Crm::InboxAgentAccess.create!(account: account, inbox: inbox, user: user, all_pipelines: false, triage: false)
    access.agent_pipelines.create!(account: account, pipeline: pipeline)
  end

  def owner_options(as:, **params)
    get "#{base}/owner_options", params: params, headers: as.create_new_auth_token
    response.parsed_body['payload']
  end

  it 'blocks nobody and lets everyone edit when the account has no access rows' do
    expect(owner_options(as: vendas_agent, card_ids: [card.id], inbox_id: inbox.id, pipeline_id: vendas.first.id))
      .to eq('cards' => { card.id.to_s => [] }, 'blocked' => [])

    get "#{base}/#{card.id}", headers: sinistro_agent.create_new_auth_token
    expect(response.parsed_body.dig('payload', 'can_edit')).to be(true)
  end

  context 'with access by funnel' do
    before do
      restrict(vendas_agent, vendas)
      restrict(sinistro_agent, sinistro)
    end

    it 'lists who cannot own the card, by card and by funnel and inbox' do
      payload = owner_options(as: vendas_agent, card_ids: [card.id], inbox_id: inbox.id, pipeline_id: vendas.first.id)

      expect(payload['cards']).to eq(card.id.to_s => [sinistro_agent.id])
      expect(payload['blocked']).to eq([sinistro_agent.id])
    end

    it 'does not reveal the setup of a funnel or a card the person cannot reach' do
      other_account = create(:account)
      foreign = create_crm_pipeline(account: other_account, user: create(:user, account: other_account, role: :administrator))
      foreign_card = other_account.crm_cards.create!(pipeline: foreign.first, stage: foreign.last, title: 'Outra conta')

      payload = owner_options(as: vendas_agent, card_ids: [foreign_card.id], inbox_id: inbox.id, pipeline_id: sinistro.first.id)

      expect(payload).to eq('cards' => {}, 'blocked' => [])
    end

    it 'lets the administrator choose anyone' do
      expect(owner_options(as: admin, card_ids: [card.id])['cards']).to eq(card.id.to_s => [])
    end

    it 'tells the screen whether the person can change the card' do
      get "#{base}/#{card.id}", headers: vendas_agent.create_new_auth_token
      expect(response.parsed_body.dig('payload', 'can_edit')).to be(true)

      card.update!(owner: sinistro_agent)
      get "#{base}/#{card.id}", headers: sinistro_agent.create_new_auth_token
      expect(response.parsed_body.dig('payload', 'can_edit')).to be(false)
    end

    it 'answers the funnel code when someone without the funnel tries to change the card' do
      card.update!(owner: sinistro_agent)

      patch "#{base}/#{card.id}", params: { card: { title: 'Outro' } }, headers: sinistro_agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body['error']).to eq('crm.access.card_funnel_required')
      expect(card.reload.title).to eq('Vendas')
    end
  end
end
