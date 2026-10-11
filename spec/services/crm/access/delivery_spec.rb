require 'rails_helper'

# Acesso por funil, parte B (#1148): o que a lista e o link escondem também não chega por tempo real, notificação,
# contador de não lidas nem rodízio. Cada caso confere quem NÃO recebe; sem linha, nada muda.
RSpec.describe 'Acesso por funil na entrega' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:vendas_agent) { create(:user, account: account, role: :agent, name: 'Vendas') }
  let(:sinistro_agent) { create(:user, account: account, role: :agent, name: 'Sinistro') }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:vendas) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let(:sinistro) { create_crm_pipeline(account: account, user: admin, name: 'Sinistro') }
  let(:conversa) { conversation_in(sinistro) }

  before do
    [vendas_agent, sinistro_agent].each { |user| create(:inbox_member, inbox: inbox, user: user) }
    restrict(vendas_agent, vendas)
    restrict(sinistro_agent, sinistro)
  end

  def restrict(user, (pipeline, _stage))
    access = Crm::InboxAgentAccess.create!(account: account, inbox: inbox, user: user, all_pipelines: false, triage: false)
    access.agent_pipelines.create!(account: account, pipeline: pipeline)
  end

  def conversation_in((pipeline, stage))
    contact = create(:contact, account: account)
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact)
    account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: contact, title: pipeline.name,
                              primary_conversation: conversation)
    conversation
  end

  describe Crm::Access::Recipients do
    it 'tira só quem o funil esconde' do
      expect(described_class.new(conversa).filter(inbox.members)).to contain_exactly(sinistro_agent)
      expect(described_class.new(conversa).blocked_user_ids).to eq([vendas_agent.id])
    end

    it 'atribuído sempre recebe' do
      conversa.update!(assignee: vendas_agent)

      expect(described_class.new(conversa).filter(inbox.members)).to contain_exactly(vendas_agent, sinistro_agent)
    end

    it 'sem linha na caixa devolve os mesmos usuários' do
      Crm::InboxAgentAccess.destroy_all
      members = inbox.members

      expect(described_class.new(conversa).filter(members)).to equal(members)
    end
  end

  describe ActionCableListener do
    it 'o evento de mensagem não vai para quem o funil esconde' do
      message = create(:message, account: account, inbox: inbox, conversation: conversa, message_type: :incoming)
      event = Events::Base.new(:'message.created', Time.zone.now, message: message)
      allow(ActionCableBroadcastJob).to receive(:perform_later)

      described_class.instance.message_created(event)

      expect(ActionCableBroadcastJob).to have_received(:perform_later) do |tokens, *_rest|
        expect(tokens).to include(sinistro_agent.pubsub_token, admin.pubsub_token)
        expect(tokens).not_to include(vendas_agent.pubsub_token)
      end
    end

    it 'o contador de não lidas não vai para quem o funil esconde' do
      account, members = Conversations::UnreadCounts::BroadcastScope.new(
        Events::Base.new(:'conversation.unread_count_changed', Time.zone.now, conversation: conversa)
      ).perform

      expect(account).to eq(conversa.account)
      expect(members).to contain_exactly(sinistro_agent)
    end
  end

  describe NotificationListener do
    it 'conversa nova não notifica quem o funil esconde' do
      builder = instance_double(NotificationBuilder, perform: true)
      allow(NotificationBuilder).to receive(:new).and_return(builder)

      described_class.instance.conversation_created(Events::Base.new(:'conversation.created', Time.zone.now, conversation: conversa))

      expect(NotificationBuilder).to have_received(:new).with(hash_including(user: sinistro_agent))
      expect(NotificationBuilder).not_to have_received(:new).with(hash_including(user: vendas_agent))
    end
  end

  describe 'rodízio' do
    it 'o V1 (AgentAssignmentService) não escolhe quem o funil esconde' do
      allow(OnlineStatusTracker).to receive(:get_available_users)
        .and_return({ vendas_agent.id.to_s => 'online', sinistro_agent.id.to_s => 'online' })
      service = AutoAssignment::AgentAssignmentService.new(conversation: conversa,
                                                           allowed_agent_ids: [vendas_agent.id, sinistro_agent.id])

      expect(service.send(:allowed_online_agent_ids)).to contain_exactly(sinistro_agent.id.to_s)
    end

    it 'o V2 (AssignmentService) filtra os candidatos pelo funil' do
      service = AutoAssignment::AssignmentService.new(inbox: inbox)

      expect(service.send(:filter_agents_by_team, inbox.inbox_members, conversa).map(&:user_id)).to contain_exactly(sinistro_agent.id)
    end

    it 'a passagem da IA para uma pessoa não escolhe quem o funil esconde' do
      selector = Crm::Ai::HandoffMemberSelector.new(inbox: inbox, account_id: account.id, conversation: conversa,
                                                    prefer_online: false)

      expect(selector.send(:eligible_members)).to contain_exactly(sinistro_agent)
    end
  end

  describe Conversations::UnreadCounts::Counter do
    it 'caixa livre segue no SCARD; só a caixa restrita é lida por id' do
      free_inbox = create(:inbox, account: account)
      create(:inbox_member, inbox: free_inbox, user: vendas_agent)
      store = Conversations::UnreadCounts::Store
      allow(store).to receive(:members_for_keys).and_return({})
      allow(store).to receive(:counts_for_keys).and_call_original
      counter = described_class.new(account: account, user: vendas_agent)
      allow(counter).to receive(:visible_inbox_ids).and_return([free_inbox.id])

      counter.send(:unread_inbox_counts)

      expect(store).to have_received(:members_for_keys).with([])
    end

    it 'conta só as não lidas que o funil deixa ver' do
      conversa_vendas = conversation_in(vendas)
      store = Conversations::UnreadCounts::Store
      allow(store).to receive(:members_for_keys) do |keys|
        keys.index_with { [conversa.id, conversa_vendas.id] }
      end
      counter = described_class.new(account: account, user: vendas_agent)
      allow(counter).to receive(:visible_inbox_ids).and_return([inbox.id])

      expect(counter.send(:unread_inbox_counts)).to eq(inbox.id.to_s => 1)
    end
  end

  describe Crm::Access::CountInvalidation do
    it 'mover o card de funil vence o cache dos contadores filtrados' do
      invalidator = instance_double(Conversations::UnreadCounts::FilteredCountInvalidator, conversation_changed!: true)
      allow(Conversations::UnreadCounts::FilteredCountInvalidator).to receive(:new).and_return(invalidator)
      card = account.crm_cards.find_by(conversation_id: conversa.id)

      card.update!(pipeline: vendas.first, stage: vendas.last)

      expect(invalidator).to have_received(:conversation_changed!).at_least(:once)
    end

    it 'conta sem acesso configurado não mexe no cache' do
      Crm::InboxAgentAccess.destroy_all
      allow(Conversations::UnreadCounts::FilteredCountInvalidator).to receive(:new).and_call_original

      account.crm_cards.find_by(conversation_id: conversa.id).update!(pipeline: vendas.first, stage: vendas.last)

      expect(Conversations::UnreadCounts::FilteredCountInvalidator).not_to have_received(:new)
    end
  end

  describe 'paridade da regra (memória do Recipients × SQL do link)' do
    it 'decide igual para cada combinação de acesso e conversa' do
      triagem = create(:conversation, account: account, inbox: inbox, contact: create(:contact, account: account))
      participando = conversation_in(vendas)
      ConversationParticipant.create!(account: account, conversation: participando, user: sinistro_agent)
      conversas = [conversa, conversation_in(vendas), triagem, participando]
      combos = [
        { all_pipelines: true, triage: false, only_own: false }, { all_pipelines: false, triage: true, only_own: false },
        { all_pipelines: false, triage: false, only_own: false }, { all_pipelines: true, triage: true, only_own: true }
      ]

      combos.each do |combo|
        access = Crm::InboxAgentAccess.find_by(user: sinistro_agent)
        access.update!(combo)
        conversas.each do |item|
          recipients = Crm::Access::Recipients.new(item).filter(inbox.members.reload).include?(sinistro_agent)
          link = Crm::Access::ConversationScope.new(user: sinistro_agent, account: account).allows?(item)

          expect(recipients).to eq(link), "acesso #{combo}, conversa #{item.id}"
        end
      end
    end

    it 'avalia todas as pessoas restritas com poucas consultas, sem crescer por pessoa' do
      extra = Array.new(6) { create(:user, account: account, role: :agent) }
      extra.each do |user|
        create(:inbox_member, inbox: inbox, user: user)
        restrict(user, vendas)
      end

      target = conversa
      queries = 0
      counter = ->(*) { queries += 1 }
      ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') do
        Crm::Access::Recipients.new(target).blocked_user_ids
      end

      expect(queries).to be <= 6
    end
  end

  describe 'Copiloto (EE)' do
    it 'não lê conversa que o funil esconde' do
      reader = Class.new { include Captain::Copilot::ConversationAccess }.new

      expect(reader.send(:accessible_conversation, account: account, user: vendas_agent, display_id: conversa.display_id)).to be_nil
      expect(reader.send(:accessible_conversation, account: account, user: sinistro_agent, display_id: conversa.display_id))
        .to eq(conversa)
    end
  end

  describe Crm::Subjects::Notifier do
    it 'o aviso de assunto não vai para quem o funil esconde' do
      tokens = described_class.new(conversa).send(:tokens)

      expect(tokens).to include(sinistro_agent.pubsub_token, admin.pubsub_token)
      expect(tokens).not_to include(vendas_agent.pubsub_token)
    end
  end
end
