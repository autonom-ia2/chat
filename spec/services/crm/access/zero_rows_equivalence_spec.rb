require 'rails_helper'

# Sem nenhuma linha de acesso por funil (o estado de produção até a tela #1149), o resultado é o mesmo de antes para
# cada papel: o escopo devolve a própria relação, sem SQL a mais, e lista, filtro, link e busca seguem a regra de caixa.
RSpec.describe 'Acesso por funil sem linhas: equivalência por papel' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:outsider) { create(:user, account: account, role: :agent) }
  let(:team_agent) { create(:user, account: account, role: :agent) }
  let(:role_agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:other_inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:team) { create(:team, account: account) }
  let(:pipeline) { create_crm_pipeline(account: account, user: admin) }
  let!(:with_card) { conversation(inbox, 'Harry com card', card: true) }
  let!(:triage) { conversation(inbox, 'Harry triagem') }
  let!(:team_conversation) { conversation(other_inbox, 'Harry do time', team: team) }
  let!(:assigned_to_role_agent) { conversation(inbox, 'Harry atribuida', assignee: role_agent) }

  def roles
    { admin: admin, agent: agent, outsider: outsider, team_agent: team_agent, role_agent: role_agent }
  end

  before do
    [agent, role_agent].each { |user| create(:inbox_member, user: user, inbox: inbox) }
    create(:team_member, team: team, user: team_agent)
    custom_role = create(:custom_role, account: account, permissions: ['conversation_participating_manage'])
    AccountUser.find_by(account: account, user: role_agent).update!(custom_role: custom_role)
  end

  def conversation(target_inbox, name, card: false, team: nil, assignee: nil)
    contact = create(:contact, account: account, name: name)
    conversa = create(:conversation, account: account, inbox: target_inbox, contact: contact, team: team, assignee: assignee)
    create(:message, account: account, inbox: target_inbox, conversation: conversa, content: "Mensagem #{name}")
    if card
      account.crm_cards.create!(pipeline: pipeline.first, stage: pipeline.last, contact: contact, title: name,
                                primary_conversation: conversa)
    end
    conversa
  end

  def account_user(user)
    AccountUser.find_by(account: account, user: user)
  end

  # O que cada papel via antes desta mudança (regra de caixa, time e função personalizada).
  def expected_list(role)
    {
      admin: [with_card, triage, team_conversation, assigned_to_role_agent],
      agent: [with_card, triage, assigned_to_role_agent],
      outsider: [],
      team_agent: [],
      role_agent: [assigned_to_role_agent]
    }.fetch(role)
  end

  it 'o escopo devolve a própria relação, para qualquer papel' do
    roles.each_value do |user|
      relation = account.conversations.where(status: :open)
      scope = Crm::Access::ConversationScope.new(user: user, account: account)

      expect(scope.apply(relation)).to equal(relation)
      expect(scope).not_to be_restricted
      expect(scope.allows?(with_card)).to be(true)
    end
  end

  it 'lista: cada papel vê o mesmo de antes' do
    roles.each do |role, user|
      result = Conversations::PermissionFilterService.new(account.conversations, user, account).perform

      expect(result).to match_array(expected_list(role)), "papel #{role}"
    end
  end

  it 'filtro avançado: cada papel vê o mesmo de antes' do
    payload = [{ attribute_key: 'status', filter_operator: 'equal_to', values: ['open'], query_operator: nil }.with_indifferent_access]
    roles.each do |role, user|
      result = Conversations::FilterService.new({ payload: payload, page: 1 }.with_indifferent_access, user, account).perform

      expect(result[:conversations]).to match_array(expected_list(role)), "papel #{role}"
    end
  end

  it 'link: o show segue a regra de caixa e de time de antes' do
    show = ->(user, record) { ConversationPolicy.new({ user: user, account: account, account_user: account_user(user) }, record).show? }

    expect(show.call(admin, team_conversation)).to be(true)
    expect(show.call(agent, with_card)).to be(true)
    expect(show.call(agent, team_conversation)).to be(false)
    expect(show.call(outsider, with_card)).to be(false)
    expect(show.call(team_agent, team_conversation)).to be(true)
    expect(show.call(role_agent, assigned_to_role_agent)).to be(true)
    expect(show.call(role_agent, triage)).to be(false)
  end

  describe 'busca' do
    before { Current.account = account }
    after { Current.account = nil }

    def search(user, type)
      SearchService.new(current_user: user, current_account: account, params: { q: 'Harry' }, search_type: type).perform
    end

    it 'conversas e mensagens: o agente vê as da caixa dele, como antes' do
      expect(search(agent, 'Conversation')[:conversations]).to contain_exactly(with_card, triage, assigned_to_role_agent)
      expect(search(agent, 'Message')[:messages].map(&:conversation_id))
        .to contain_exactly(with_card.id, triage.id, assigned_to_role_agent.id)
      expect(search(outsider, 'Conversation')[:conversations]).to be_empty
    end
  end

  describe 'entre contas' do
    def other_conversation
      @other_conversation ||= begin
        other_account = create(:account)
        AccountUser.create!(account: other_account, user: agent, role: :agent)
        other_inbox_of_account = create(:inbox, account: other_account)
        create(:inbox_member, user: agent, inbox: other_inbox_of_account)
        create(:conversation, account: other_account, inbox: other_inbox_of_account,
                              contact: create(:contact, account: other_account, name: 'Harry de outra conta'))
      end
    end

    before { other_conversation }

    it 'o link de uma conta não abre conversa de outra' do
      policy = ConversationPolicy.new({ user: agent, account: account, account_user: account_user(agent) }, other_conversation)

      expect(policy.show?).to be(false)
    end

    it 'a busca de uma conta não traz conversa de outra' do
      Current.account = account
      result = SearchService.new(current_user: agent, current_account: account, params: { q: 'Harry' },
                                 search_type: 'Conversation').perform
      Current.account = nil

      expect(result[:conversations]).not_to include(other_conversation)
    end
  end
end
