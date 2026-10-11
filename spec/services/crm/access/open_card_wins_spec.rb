require 'rails_helper'

# Card aberto manda (#1148, decisão do Rodrigo em 11/10): com card aberto na conversa, só os funis dos abertos liberam a
# conversa; ganho e perdido só prendem quando não há nenhum aberto; resolvido, cancelado e arquivado nunca prendem. A
# lista (SQL do ConversationScope) e o tempo real e o rodízio (Recipients, em memória) têm de concordar em cada caso.
RSpec.describe 'Acesso por funil: card aberto manda' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:vendas_agent) { create_crm_agent(account: account, name: 'Vendas').first }
  let(:sinistro_agent) { create_crm_agent(account: account, name: 'Sinistro').first }
  let(:triagem_agent) { create_crm_agent(account: account, name: 'Triagem').first }
  let(:agents) { [vendas_agent, sinistro_agent, triagem_agent] }
  let(:inbox) { create_crm_inbox(account: account, members: agents) }
  let(:vendas) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let(:sinistro) { create_crm_pipeline(account: account, user: admin, name: 'Sinistro') }
  let(:conversa) { create_crm_conversation(account: account, inbox: inbox, contact: create(:contact, account: account)) }

  def restrict!
    [[vendas_agent, vendas, false], [sinistro_agent, sinistro, false], [triagem_agent, nil, true]].each do |user, pipeline, triage|
      access = Crm::InboxAgentAccess.create!(account: account, inbox: inbox, user: user, all_pipelines: false, triage: triage)
      access.agent_pipelines.create!(account: account, pipeline: pipeline.first) if pipeline
    end
  end

  # linked: o card entra pela crm_card_conversations, sem ser a conversa principal dele.
  def card(pipeline, status, linked: false)
    created = account.crm_cards.create!(pipeline: pipeline.first, stage: pipeline.last, title: "#{pipeline.first.name} #{status}",
                                        inbox: inbox, contact: conversa.contact, primary_conversation: linked ? nil : conversa)
    Crm::CardConversation.create!(account: account, card: created, conversation: conversa) if linked
    created.update_columns(status: Crm::Card.statuses[status]) unless status == :open # rubocop:disable Rails/SkipsModelValidations
    created
  end

  # Quem vê pela lista (SQL) e quem não é barrado no tempo real (memória): os dois precisam dar o mesmo resultado.
  def seen_by_list
    agents.select { |agent| Crm::Access::ConversationScope.new(user: agent, account: account).allows?(conversa.reload) }
  end

  def seen_by_realtime
    agents - User.where(id: Crm::Access::Recipients.new(conversa.reload).blocked_user_ids).to_a
  end

  def expect_seen_by(*expected)
    expect(seen_by_list).to match_array(expected)
    expect(seen_by_realtime).to match_array(expected)
  end

  describe 'com acesso por funil' do
    before { restrict! }

    it '1 aberto em Vendas e 1 ganho em Sinistro: só Vendas vê (o aberto manda)' do
      card(vendas, :open)
      card(sinistro, :won)

      expect_seen_by(vendas_agent)
    end

    it 'aberto vinculado e ganho principal: o aberto manda' do
      card(vendas, :open, linked: true)
      card(sinistro, :won)

      expect_seen_by(vendas_agent)
    end

    it 'aberto principal e ganho vinculado: o aberto manda' do
      card(vendas, :open)
      card(sinistro, :won, linked: true)

      expect_seen_by(vendas_agent)
    end

    it 'dois abertos em funis diferentes: os dois veem' do
      card(vendas, :open)
      card(sinistro, :open, linked: true)

      expect_seen_by(vendas_agent, sinistro_agent)
    end

    it 'atendente do Sinistro continua vendo mesmo com aberto em Vendas' do
      conversa.update!(assignee: sinistro_agent)
      card(vendas, :open)
      card(sinistro, :won)

      expect_seen_by(vendas_agent, sinistro_agent)
    end

    it 'só perdido: o funil dele vê, a triagem não' do
      card(vendas, :lost)

      expect_seen_by(vendas_agent)
    end

    it 'o aberto vira ganho: a sincronização em tempo real entra na fila para a conversa' do
      aberto = card(vendas, :open)
      card(sinistro, :won)
      Crm::Access::CountInvalidation.sync_started!([conversa.id])

      expect { aberto.update!(status: :won) }.to have_enqueued_job(Crm::Access::VisibilitySyncJob).with(array_including(conversa.id))
      expect_seen_by(vendas_agent, sinistro_agent)
    end

    it 'só ganho e perdido, em funis diferentes: os dois funis veem' do
      card(vendas, :lost)
      card(sinistro, :won)

      expect_seen_by(vendas_agent, sinistro_agent)
    end

    it 'só resolvido (funil de atendimento): solta para a triagem' do
      sinistro.first.update!(counts_as_sale: false)
      card(sinistro, :resolved)

      expect_seen_by(triagem_agent)
    end

    it 'o aberto fecha: o ganho volta a prender a conversa ao funil dele' do
      aberto = card(vendas, :open)
      card(sinistro, :won)
      aberto.update_columns(status: Crm::Card.statuses[:archived]) # rubocop:disable Rails/SkipsModelValidations

      expect_seen_by(sinistro_agent)
    end
  end

  describe 'sem nenhuma linha de acesso (todas as contas hoje)' do
    it 'todo mundo da caixa vê, como antes' do
      card(vendas, :open)
      card(sinistro, :won)

      expect_seen_by(*agents)
    end
  end
end
