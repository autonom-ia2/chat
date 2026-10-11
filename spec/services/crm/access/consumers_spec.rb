require 'rails_helper'

# O acesso por funil (#1148) chega a quem lista, abre e busca conversas. Cada caso confere o que a pessoa NÃO vê.
RSpec.describe 'Acesso por funil nos pontos de leitura' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent_and_account_user) { create_crm_agent(account: account, name: 'Vendas') }
  let(:agent) { agent_and_account_user.first }
  let(:inbox) { create_crm_inbox(account: account, members: [agent]) }
  let(:vendas) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let(:sinistro) { create_crm_pipeline(account: account, user: admin, name: 'Sinistro') }
  let!(:conversa_vendas) { conversation_with_card(vendas, 'Harry Vendas') }
  let!(:conversa_sinistro) { conversation_with_card(sinistro, 'Harry Sinistro') }

  before do
    access = Crm::InboxAgentAccess.create!(account: account, inbox: inbox, user: agent, all_pipelines: false, triage: false)
    access.agent_pipelines.create!(account: account, pipeline: vendas.first)
  end

  def conversation_with_card((pipeline, stage), name)
    contact = account.contacts.create!(name: name, phone_number: "+55119#{rand(10_000_000..99_999_999)}")
    conversa = create_crm_conversation(account: account, inbox: inbox, contact: contact)
    account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: contact, title: name, primary_conversation: conversa)
    create(:message, account: account, inbox: inbox, conversation: conversa, content: "Mensagem de #{name}")
    conversa
  end

  describe Conversations::PermissionFilterService do
    it 'a lista do agente traz só o funil dele' do
      result = described_class.new(account.conversations, agent, account).perform

      expect(result).to contain_exactly(conversa_vendas)
    end

    it 'o caminho com dica de plano (filtro seletivo) aplica a mesma regra' do
      result = described_class.new(account.conversations, agent, account, plan_hint_selective_filter: true).perform

      expect(result).to contain_exactly(conversa_vendas)
    end

    it 'administrador continua vendo tudo' do
      expect(described_class.new(account.conversations, admin, account).perform).to include(conversa_vendas, conversa_sinistro)
    end
  end

  describe ConversationPolicy do
    it 'não abre pelo link a conversa de outro funil' do
      expect(described_class.new({ user: agent, account: account, account_user: agent_and_account_user.last },
                                 conversa_sinistro).show?).to be(false)
      expect(described_class.new({ user: agent, account: account, account_user: agent_and_account_user.last },
                                 conversa_vendas).show?).to be(true)
    end

    it 'o time não fura o funil' do
      team = create(:team, account: account)
      create(:team_member, team: team, user: agent)
      conversa_sinistro.update!(team: team)

      expect(described_class.new({ user: agent, account: account, account_user: agent_and_account_user.last },
                                 conversa_sinistro).show?).to be(false)
    end

    it 'atribuída a ele abre mesmo em outro funil' do
      conversa_sinistro.update!(assignee: agent)

      expect(described_class.new({ user: agent, account: account, account_user: agent_and_account_user.last },
                                 conversa_sinistro).show?).to be(true)
    end
  end

  describe SearchService do
    before { Current.account = account }
    after { Current.account = nil }

    def search(type)
      described_class.new(current_user: agent, current_account: account, params: { q: 'Harry' }, search_type: type).perform
    end

    it 'a busca de conversas não traz outro funil' do
      expect(search('Conversation')[:conversations]).to contain_exactly(conversa_vendas)
    end

    it 'a busca de mensagens não traz mensagem de conversa de outro funil' do
      expect(search('Message')[:messages].map(&:conversation_id)).to contain_exactly(conversa_vendas.id)
    end
  end
end
