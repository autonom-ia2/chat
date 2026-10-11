require 'rails_helper'

# Acesso por funil, parte C (#1148): o CRM (Kanban, drawer, mover, lote, upsert), os avisos de card e de chamada e a
# troca de funil seguem a mesma regra da lista de conversas. Cada caso confere o que a pessoa NÃO vê ou não consegue.
RSpec.describe 'Acesso por funil no CRM' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent_and_account_user) { create_crm_agent(account: account, name: 'Vendas') }
  let(:vendas_agent) { agent_and_account_user.first }
  let(:sinistro_agent) { create_crm_agent(account: account, name: 'Sinistro').first }
  let(:inbox) { create_crm_inbox(account: account, members: [vendas_agent, sinistro_agent]) }
  let(:vendas) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let(:sinistro) { create_crm_pipeline(account: account, user: admin, name: 'Sinistro') }
  let(:conversa) { create_crm_conversation(account: account, inbox: inbox, contact: create(:contact, account: account)) }
  let(:card_sinistro) do
    account.crm_cards.create!(pipeline: sinistro.first, stage: sinistro.last, title: 'Sinistro', contact: conversa.contact,
                              inbox: inbox, primary_conversation: conversa)
  end
  let(:card_vendas) do
    account.crm_cards.create!(pipeline: vendas.first, stage: vendas.last, title: 'Vendas', inbox: inbox,
                              contact: create(:contact, account: account))
  end

  around do |example|
    with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run }
  end

  before do
    restrict(vendas_agent, vendas)
    restrict(sinistro_agent, sinistro)
  end

  def restrict(user, (pipeline, _stage), only_own: false)
    access = Crm::InboxAgentAccess.create!(account: account, inbox: inbox, user: user, all_pipelines: false, triage: false,
                                           only_own: only_own)
    access.agent_pipelines.create!(account: account, pipeline: pipeline)
  end

  def account_user(user)
    AccountUser.find_by(account: account, user: user)
  end

  describe Crm::Access::CardScope do
    def visible(user)
      described_class.new(user: user, account: account).apply(account.crm_cards).to_a
    end

    it 'o Kanban não mostra card de funil que a pessoa não tem' do
      card_vendas
      card_sinistro

      expect(visible(vendas_agent)).to contain_exactly(card_vendas)
      expect(visible(sinistro_agent)).to contain_exactly(card_sinistro)
    end

    it 'card de que é dona, ou da conversa que atende, aparece mesmo em outro funil' do
      card_sinistro.update!(owner: vendas_agent)

      expect(visible(vendas_agent)).to include(card_sinistro)
    end

    it 'Só as suas: só os cards dela' do
      Crm::InboxAgentAccess.find_by(user: vendas_agent).update!(only_own: true)

      expect(visible(vendas_agent)).to be_empty
    end

    it 'card avulso (sem caixa) não é restringido aqui' do
      avulso = account.crm_cards.create!(pipeline: sinistro.first, stage: sinistro.last, title: 'Avulso')

      expect(visible(vendas_agent)).to include(avulso)
    end

    it 'VisibleScopeQuery (Kanban, lista, calendário) passa pelo funil' do
      result = Crm::Cards::VisibleScopeQuery.new(scope: account.crm_cards, account: account, user: vendas_agent,
                                                 account_user: account_user(vendas_agent)).perform

      expect(result).to contain_exactly(card_vendas)
    end
  end

  describe Crm::Conversations::Visibility do
    it 'o CRM (resumo, calendário, drawer) não abre conversa de outro funil' do
      card_sinistro
      visibility = described_class.new(account: account, user: vendas_agent, account_user: account_user(vendas_agent))

      expect(visibility.visible?(conversa)).to be(false)
      expect(visibility.scope(account.conversations)).not_to include(conversa)
    end
  end

  describe 'mover e gravar card num funil', type: :request do
    it 'não move card para um funil que a pessoa não tem' do
      card_vendas
      post "/api/v1/accounts/#{account.id}/crm/cards/#{card_vendas.id}/move",
           params: { stage_id: sinistro.last.id }, headers: vendas_agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized).or have_http_status(:forbidden)
      expect(card_vendas.reload.pipeline_id).to eq(vendas.first.id)
    end

    it 'move dentro do próprio funil' do
      outra_etapa = create_crm_stage(account: account, pipeline: vendas.first, name: 'Proposta')
      post "/api/v1/accounts/#{account.id}/crm/cards/#{card_vendas.id}/move",
           params: { stage_id: outra_etapa.id }, headers: vendas_agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
    end
  end

  describe Crm::Cards::BulkAction do
    it 'o lote não move card para funil que a pessoa não tem' do
      result = described_class.new(account: account, user: vendas_agent, account_user: account_user(vendas_agent),
                                   ids: [card_vendas.id], action: 'move', payload: { stage_id: sinistro.last.id }).perform

      expect(result[:failed]).to contain_exactly({ id: card_vendas.id, error: 'forbidden' })
      expect(card_vendas.reload.pipeline_id).to eq(vendas.first.id)
    end
  end

  describe Crm::Cards::Broadcaster do
    it 'o card não vai em tempo real para quem o funil esconde' do
      users = described_class.recipient_users_for(card_sinistro)

      expect(users).to include(sinistro_agent, admin)
      expect(users).not_to include(vendas_agent)
    end
  end

  describe Crm::Access::CallStreams do
    it 'com acesso configurado, a chamada vai só a quem vê a conversa (não ao canal da conta)' do
      card_sinistro
      streams = described_class.for(conversa)

      expect(streams).to include(sinistro_agent.pubsub_token, admin.pubsub_token)
      expect(streams).not_to include(vendas_agent.pubsub_token, "account_#{account.id}")
    end

    it 'sem acesso configurado, segue no canal da conta' do
      other = create(:account)
      other_conversation = create(:conversation, account: other, inbox: create(:inbox, account: other))

      expect(described_class.for(other_conversation)).to eq(["account_#{other.id}"])
    end
  end

  describe Crm::Access::VisibilitySync do
    it 'quem passou a ver recebe a conversa e quem deixou de ver a tira da lista' do
      card_sinistro
      allow(ActionCableBroadcastJob).to receive(:perform_later)

      described_class.perform(conversa)

      expect(ActionCableBroadcastJob).to have_received(:perform_later)
        .with(array_including(sinistro_agent.pubsub_token), Events::Types::CONVERSATION_UPDATED, anything)
      expect(ActionCableBroadcastJob).to have_received(:perform_later)
        .with([vendas_agent.pubsub_token], 'conversation.access_revoked', hash_including(id: conversa.id))
    end

    it 'mudar o card de funil agenda a sincronização da conversa' do
      card_sinistro

      expect { card_sinistro.update!(pipeline: vendas.first, stage: vendas.last) }
        .to have_enqueued_job(Crm::Access::VisibilitySyncJob).with(array_including(conversa.id))
    end
  end

  describe 'sem nenhuma linha de acesso (todas as contas hoje)' do
    it 'cards, visibilidade do CRM e pipeline seguem como antes' do
      other = create(:account)
      agent = create(:user, account: other, role: :agent)
      cards = other.crm_cards.where(status: :open)
      conversations = other.conversations

      expect(Crm::Access::CardScope.new(user: agent, account: other).apply(cards)).to equal(cards)
      expect(Crm::Access::CardScope.new(user: agent, account: other).pipeline_allowed?(1, 2)).to be(true)
      expect(Crm::Access::ConversationScope.new(user: agent, account: other).apply(conversations)).to equal(conversations)
    end
  end
end
