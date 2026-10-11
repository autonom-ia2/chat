require 'rails_helper'

# Sem nenhuma linha de acesso por funil (todas as contas hoje), cada caminho de entrega devolve o mesmo que a main e
# não consulta a tabela de acesso no evento quente (#1148, parte B).
RSpec.describe 'Acesso por funil sem linhas: entrega igual à main' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: create(:contact, account: account)) }

  before do
    [agent, other].each { |user| create(:inbox_member, inbox: inbox, user: user) }
    admin
  end

  def access_table_queries(&)
    queries = []
    callback = ->(*, payload) { queries << payload[:sql] if payload[:sql].include?('crm_inbox_agent_accesses') }
    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record', &)
    queries
  end

  it 'evento de mensagem não consulta a tabela de acesso (atalho por conta)' do
    message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming)
    event = Events::Base.new(:'message.created', Time.zone.now, message: message)
    allow(ActionCableBroadcastJob).to receive(:perform_later)
    Crm::Access::AccountFlag.any?(account.id)

    queries = access_table_queries { ActionCableListener.instance.message_created(event) }

    expect(queries).to be_empty
  end

  it 'o atalho vence quando a primeira linha é criada' do
    expect(Crm::Access::AccountFlag.any?(account.id)).to be(false)

    Crm::InboxAgentAccess.create!(account: account, inbox: inbox, user: agent, all_pipelines: false)

    expect(Crm::Access::AccountFlag.any?(account.id)).to be(true)
  end

  it 'ActionCable: mesmos tokens da main (membros + administradores)' do
    tokens = ActionCableListener.instance.send(:user_tokens, account, Crm::Access::Recipients.inbox_members(conversation))

    expect(tokens).to match_array([agent, other, admin].map(&:pubsub_token).uniq)
  end

  it 'notificações e não lidas: os mesmos membros da main' do
    expect(Crm::Access::Recipients.inbox_members(conversation)).to match_array(inbox.members)
    _account, members = Conversations::UnreadCounts::BroadcastScope.new(
      Events::Base.new(:'conversation.unread_count_changed', Time.zone.now, conversation: conversation)
    ).perform
    expect(members).to match_array(inbox.members)
  end

  it 'rodízio V1 e V2: os mesmos candidatos' do
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return({ agent.id.to_s => 'online', other.id.to_s => 'online' })
    v1 = AutoAssignment::AgentAssignmentService.new(conversation: conversation, allowed_agent_ids: [agent.id, other.id])
    members = inbox.inbox_members

    expect(v1.send(:allowed_online_agent_ids)).to contain_exactly(agent.id.to_s, other.id.to_s)
    expect(AutoAssignment::AssignmentService.new(inbox: inbox).send(:filter_agents_by_team, members, conversation)).to equal(members)
  end

  it 'contador de não lidas: segue no SCARD, sem ler conjunto por id' do
    allow(Conversations::UnreadCounts::Store).to receive(:members_for_keys)
    counter = Conversations::UnreadCounts::Counter.new(account: account, user: agent)
    allow(counter).to receive(:visible_inbox_ids).and_return([inbox.id])

    counter.send(:unread_inbox_counts)

    expect(Conversations::UnreadCounts::Store).not_to have_received(:members_for_keys)
  end

  it 'Copiloto: as mesmas conversas da regra de caixa' do
    reader = Class.new { include Captain::Copilot::ConversationAccess }.new
    team_conversation = create(:conversation, account: account, inbox: create(:inbox, account: account),
                                              contact: create(:contact, account: account))

    expect(reader.send(:accessible_conversations, account: account, user: agent)).to contain_exactly(conversation)
    expect(reader.send(:accessible_conversations, account: account, user: admin)).to include(conversation, team_conversation)
  end

  it 'chamada de WhatsApp: os mesmos destinos (membros online e, sem ninguém online, membros + admins)' do
    service = Whatsapp::IncomingCallService.allocate
    service.instance_variable_set(:@inbox, inbox)
    allow(service).to receive(:inbox).and_return(inbox)
    call = instance_double(Call, conversation: conversation)

    expect(service.send(:fallback_agent_streams, call)).to match_array([agent, other, admin].map(&:pubsub_token).uniq)
  end

  describe Crm::Access::AccountFlag do
    it 'corrida: um "0" lido antes da criação não apaga o "1" que a criação gravou (falha fechado)' do
      key = described_class.key(account.id)
      Redis::Alfred.delete(key)
      allow(Crm::InboxAgentAccess).to receive(:exists?).and_wrap_original do |original, *args, **kwargs|
        result = original.call(*args, **kwargs) # t0: o leitor vê 0 linhas
        Crm::InboxAgentAccess.create!(account: account, inbox: inbox, user: agent, all_pipelines: false) # t1: criação
        result
      end

      expect(described_class.any?(account.id)).to be(true) # t2: o leitor não sobrescreve
      expect(Redis::Alfred.get(key)).to eq('1')
    end

    it 'apagar o acesso remove a chave e a próxima leitura recalcula' do
      access = Crm::InboxAgentAccess.create!(account: account, inbox: inbox, user: agent, all_pipelines: false)
      expect(described_class.any?(account.id)).to be(true)

      access.destroy!

      expect(Redis::Alfred.get(described_class.key(account.id))).to be_nil
      expect(described_class.any?(account.id)).to be(false)
    end
  end
end
