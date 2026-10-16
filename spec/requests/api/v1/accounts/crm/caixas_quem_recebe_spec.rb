require 'rails_helper'

# Canais de cada funil (#1140, correção 1): quem recebe cada assunto vem do servidor, pela regra do motor de entrega
# (Crm::Entrega::QuemCuida), com o que a tela marcou e ainda não salvou.
RSpec.describe 'CRM Caixas no CRM: quem recebe', type: :request do
  around do |example|
    with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run }
  end

  let!(:account_and_admin) { create_account_and_user }
  let(:account) { account_and_admin.first }
  let(:admin) { account_and_admin.last }
  let(:ana) { create_crm_agent(account: account, name: 'Ana Ribeiro').first }
  let(:bruno) { create_crm_agent(account: account, name: 'Bruno Lima').first }
  let(:vendas) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let(:pos_venda) { create_crm_pipeline(account: account, user: admin, name: 'Pós-venda') }
  let(:url) { "/api/v1/accounts/#{account.id}/crm/caixas/#{inbox.id}" }
  let(:contact) { create(:contact, account: account) }

  before { account.enable_features!('crm_configurar_caixas') }

  def caixa(**extra)
    {
      pipeline_ids: [vendas.first.id, pos_venda.first.id], modo: 'off',
      people: [
        { id: ana.id, triage: true, only_own: false, pipeline_ids: [vendas.first.id] },
        { id: bruno.id, triage: false, only_own: true, pipeline_ids: [pos_venda.first.id] }
      ]
    }.merge(extra)
  end

  def quem_recebe(user: admin, dados: caixa)
    post "#{url}/quem_recebe", params: { caixa: dados }, headers: auth_headers(user), as: :json
    response.parsed_body.dig('payload', 'quem_recebe')
  end

  context 'without an administrator in the inbox' do
    let(:inbox) { create_crm_inbox(account: account, name: 'WhatsApp', members: [ana, bruno]) }

    it 'leaves out who only sees their own, and says nobody receives the funnel only they had' do
      quem = quem_recebe

      expect(response).to have_http_status(:ok)
      expect(quem['triagem']).to eq([ana.id])
      expect(quem['funis']).to eq(vendas.first.id.to_s => [ana.id], pos_venda.first.id.to_s => [])
    end

    it 'writes nothing' do
      quem_recebe

      expect(Crm::InboxAgentAccess.where(inbox: inbox)).to be_empty
      expect(account.crm_pipeline_inboxes.where(inbox: inbox)).to be_empty
    end

    it 'is what the delivery engine decides once the screen saves' do
      quem = quem_recebe
      put url, params: { caixa: caixa }, headers: auth_headers(admin), as: :json
      expect(response).to have_http_status(:ok)

      [vendas, pos_venda].each do |funil|
        conversa = create(:conversation, account: account, inbox: inbox, contact: contact, status: :open).reload
        card = account.crm_cards.create!(pipeline: funil.first, stage: funil.last, contact: contact, title: funil.first.name,
                                         primary_conversation: conversa, inbox: inbox)
        motor = Crm::Entrega::QuemCuida.new(conversation: conversa, card: card).pessoas.map(&:id)
        expect(motor).to eq(quem['funis'][funil.first.id.to_s])
      end
      sem_card = create(:conversation, account: account, inbox: inbox, contact: contact, status: :open).reload
      expect(Crm::Entrega::QuemCuida.new(conversation: sem_card).pessoas.map(&:id)).to eq(quem['triagem'])
    end

    it 'follows the screen, not what is saved: unmarking "Só as que atende" makes Bruno receive' do
      put url, params: { caixa: caixa }, headers: auth_headers(admin), as: :json

      dados = caixa(people: [{ id: ana.id, triage: true, only_own: false, pipeline_ids: [vendas.first.id] },
                             { id: bruno.id, triage: false, only_own: false, pipeline_ids: [pos_venda.first.id] }])

      expect(quem_recebe(dados: dados)['funis'][pos_venda.first.id.to_s]).to eq([bruno.id])
    end

    it 'with a single funnel, whoever has it also takes the conversations without a subject' do
      dados = caixa(pipeline_ids: [vendas.first.id], modo: 'off',
                    people: [{ id: ana.id, triage: false, only_own: false, pipeline_ids: [vendas.first.id] },
                             { id: bruno.id, triage: false, only_own: false, pipeline_ids: [] }])

      quem = quem_recebe(dados: dados)

      expect(quem['triagem']).to eq([ana.id])
      expect(quem['funis']).to eq(vendas.first.id.to_s => [ana.id])
    end
  end

  context 'with an integration user in the inbox' do
    let(:robo) { create_crm_agent(account: account, name: 'n8n').first }
    let(:inbox) { create_crm_inbox(account: account, name: 'WhatsApp', members: [ana, bruno, robo]) }

    before { AccountUser.find_by(account: account, user: robo).update!(integration: true) }

    it 'never counts the integration user, as the engine (n8n and MCP never answer)' do
      quem = quem_recebe

      expect(quem['triagem']).to eq([ana.id])
      expect(quem['funis'].values.flatten).not_to include(robo.id)
    end
  end

  context 'with an administrator in the inbox' do
    let(:inbox) { create_crm_inbox(account: account, name: 'WhatsApp', members: [admin, ana, bruno]) }

    it 'counts the administrator in every subject, as the engine does' do
      quem = quem_recebe

      expect(quem['funis'][pos_venda.first.id.to_s]).to eq([admin.id])
      expect(quem['funis'][vendas.first.id.to_s]).to contain_exactly(admin.id, ana.id)
    end
  end

  context 'without permission or flag' do
    let(:inbox) { create_crm_inbox(account: account, name: 'WhatsApp', members: [ana, bruno]) }

    it 'refuses agents' do
      quem_recebe(user: ana)

      expect(response).to have_http_status(:unauthorized)
    end

    it 'answers 404 without the account flag' do
      account.disable_features!('crm_configurar_caixas')
      quem_recebe

      expect(response).to have_http_status(:not_found)
    end
  end
end
