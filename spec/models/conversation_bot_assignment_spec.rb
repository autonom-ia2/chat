require 'rails_helper'

# Robô atendendo fica como o atribuído da conversa (#1377, decisão do Rodrigo em 12/10): sem "não atribuída" falsa
# enquanto um robô atende, e conversa de robô nunca fica pendente.
RSpec.describe 'Robô atribuído à conversa' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:bot) { create(:agent_bot, account: account, name: 'Ana Maciel') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :open).reload }

  before { create(:inbox_member, inbox: inbox, user: agent) }

  def bot_reply(conv = conversation, **attrs)
    create(:message, account: account, inbox: inbox, conversation: conv, message_type: :outgoing, sender: bot,
                     content: 'Olá', **attrs)
  end

  describe 'quando o robô responde' do
    it 'numa conversa pendente, a deixa aberta no nome do robô' do
      conversation.update!(status: :pending)

      bot_reply

      expect(conversation.reload).to have_attributes(ai_assignee: bot, status: 'open')
    end

    it 'fica como o atribuído da conversa, que continua aberta' do
      bot_reply

      expect(conversation.reload.ai_assignee).to eq(bot)
      expect(conversation.status).to eq('open')
      expect(Conversation.unassigned).not_to include(conversation)
    end

    it 'não tira a conversa de uma pessoa nem conta nota privada' do
      conversation.update!(assignee: agent)
      bot_reply
      expect(conversation.reload.assignee).to eq(agent)
      expect(conversation.ai_assignee).to be_nil

      other = create(:conversation, account: account, inbox: inbox, status: :open)
      bot_reply(other, private: true)
      expect(other.reload.ai_assignee).to be_nil
    end
  end

  describe 'atribuir pelo seletor' do
    it 'deixa a conversa aberta no nome do robô, nunca pendente' do
      conversation.update!(status: :pending)

      Conversations::AssignmentService.new(conversation: conversation, assignee_id: bot.id, assignee_type: 'AgentBot').perform

      expect(conversation.reload.ai_assignee).to eq(bot)
      expect(conversation.status).to eq('open')
    end

    it 'desatribuir numa caixa com robô devolve a conversa a ele, aberta mesmo se estava pendente' do
      create(:agent_bot_inbox, inbox: inbox, agent_bot: bot)
      conversation.update!(assignee: agent, status: :pending)

      Conversations::AssignmentService.new(conversation: conversation, assignee_id: nil).perform

      expect(conversation.reload.assignee).to be_nil
      expect(conversation.ai_assignee).to eq(bot)
      expect(conversation.status).to eq('open')
    end
  end

  describe 'passagem para pessoa' do
    before { create(:agent_bot_inbox, inbox: inbox, agent_bot: bot) }

    it 'sem ninguém que assuma agora, continua no nome do robô, aberta e à espera de pessoa' do
      conversation.update!(ai_assignee: bot, status: :pending)

      conversation.bot_handoff!

      expect(conversation.reload.ai_assignee).to eq(bot)
      expect(conversation.status).to eq('open')
      expect(conversation.waiting_since).to be_present
      expect(conversation).to be_bot_handoff_waiting
      expect(Conversation.awaiting_person).to include(conversation)
    end

    it 'não apaga um atributo gravado por outra conexão antes da passagem' do
      conversation.update!(ai_assignee: bot)
      stale = Conversation.find(conversation.id)
      # rubocop:disable Rails/SkipsModelValidations -- escrita "por fora" (outra conexão) é o ponto do teste
      Conversation.where(id: conversation.id).update_all(additional_attributes: { 'mail_subject' => 'Seguro auto' })
      # rubocop:enable Rails/SkipsModelValidations

      stale.bot_handoff!

      expect(conversation.reload.additional_attributes).to include('mail_subject' => 'Seguro auto')
      expect(conversation).to be_bot_handoff_waiting
    end

    it 'avisa a tela na hora quando só a marca muda (robô já no nome, conversa já aberta)' do
      conversation.update!(ai_assignee: bot)
      allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original

      conversation.bot_handoff!

      expect(Rails.configuration.dispatcher).to have_received(:dispatch)
        .with(Events::Types::CONVERSATION_UPDATED, anything, hash_including(conversation: conversation))
    end

    it 'a resposta do robô durante a espera não tira a conversa de "Não atendidas"' do
      conversation.update!(ai_assignee: bot)
      conversation.bot_handoff!

      bot_reply

      expect(conversation.reload.waiting_since).to be_present
    end

    it 'quando uma pessoa entra na conversa, o robô sai e a espera acaba' do
      conversation.update!(ai_assignee: bot)
      conversation.bot_handoff!

      Conversations::AssignmentService.new(conversation: conversation, assignee_id: agent.id).perform

      expect(conversation.reload.assignee).to eq(agent)
      expect(conversation.ai_assignee).to be_nil
      expect(conversation).not_to be_bot_handoff_waiting
    end

    it 'com uma pessoa já na conversa, não volta para o robô' do
      conversation.update!(assignee: agent)

      conversation.bot_handoff!

      expect(conversation.reload.assignee).to eq(agent)
      expect(conversation.ai_assignee).to be_nil
      expect(conversation).not_to be_bot_handoff_waiting
    end

    it 'resolver encerra a espera' do
      conversation.update!(ai_assignee: bot)
      conversation.bot_handoff!

      conversation.update!(status: :resolved)

      expect(conversation.reload).not_to be_bot_handoff_waiting
    end

    it 'com rodízio antigo e uma pessoa online, a pessoa recebe a conversa na hora' do
      inbox.update!(enable_auto_assignment: true)
      allow(OnlineStatusTracker).to receive(:get_available_users).and_return({ agent.id.to_s => 'online' })
      conversation.update!(ai_assignee: bot)

      conversation.bot_handoff!

      expect(conversation.reload.assignee).to eq(agent)
      expect(conversation.ai_assignee).to be_nil
      expect(conversation).not_to be_bot_handoff_waiting
    end

    it 'com rodízio novo, o rodízio entrega a conversa à espera a uma pessoa' do
      account.enable_features('assignment_v2')
      account.save!
      inbox.update!(enable_auto_assignment: true)
      create(:inbox_assignment_policy, inbox: inbox, assignment_policy: create(:assignment_policy, account: account, enabled: true))
      allow(OnlineStatusTracker).to receive(:get_available_users).and_return({ agent.id.to_s => 'online' })
      conversation.update!(ai_assignee: bot)
      allow(AutoAssignment::AssignmentJob).to receive(:enqueue_for_inbox)

      conversation.bot_handoff!
      expect(AutoAssignment::AssignmentJob).to have_received(:enqueue_for_inbox).with(inbox.id)
      expect(conversation.reload.ai_assignee).to eq(bot)

      AutoAssignment::AssignmentService.new(inbox: inbox).perform_bulk_assignment(limit: 10)

      expect(conversation.reload.assignee).to eq(agent)
      expect(conversation.ai_assignee).to be_nil
      expect(conversation).not_to be_bot_handoff_waiting
    end

    it 'o rodízio novo não pega conversa que o robô atende sem passagem' do
      account.enable_features('assignment_v2')
      account.save!
      conversation.update!(ai_assignee: bot)

      expect(Conversation.awaiting_person).not_to include(conversation)
    end

    it 'desligar o robô devolve a conversa à equipe, sem robô e sem espera' do
      conversation.update!(ai_assignee: bot)

      agent_ia = Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'custom', status: :active, enabled: true,
                                                  instruction: 'Atenda o cliente.')
      Autonomia::Agents::AgentInbox.create!(agent: agent_ia, inbox: inbox, account: account, agent_bot: bot).release_bot_conversations!

      expect(conversation.reload.ai_assignee).to be_nil
      expect(conversation).not_to be_bot_handoff_waiting
      expect(Conversation.unassigned).to include(conversation)
    end
  end

  describe 'aba "Não atribuídas" (opção b)' do
    let(:admin) { create(:user, account: account, role: :administrator) }

    def unassigned_tab
      Current.account = account
      ConversationFinder.new(admin, { assignee_type: 'unassigned', status: 'open' }).perform
    end

    it 'mostra e conta a conversa à espera de pessoa, com o robô no nome' do
      create(:agent_bot_inbox, inbox: inbox, agent_bot: bot)
      conversation.update!(ai_assignee: bot)
      conversation.bot_handoff!

      result = unassigned_tab

      expect(result[:conversations]).to include(conversation)
      expect(result[:count][:unassigned_count]).to eq(1)
    end

    it 'não mostra a conversa que o robô atende sem passagem, nem a que tem pessoa' do
      conversation.update!(ai_assignee: bot)
      with_person = create(:conversation, account: account, inbox: inbox, status: :open, assignee: agent)

      result = unassigned_tab

      expect(result[:conversations]).not_to include(conversation, with_person)
      expect(result[:count][:unassigned_count]).to eq(0)
    end

    it 'sai da aba quando uma pessoa entra na conversa' do
      create(:agent_bot_inbox, inbox: inbox, agent_bot: bot)
      conversation.update!(ai_assignee: bot)
      conversation.bot_handoff!

      Conversations::AssignmentService.new(conversation: conversation, assignee_id: agent.id).perform

      expect(unassigned_tab[:conversations]).not_to include(conversation)
    end
  end

  describe 'responsável no CRM' do
    let(:admin) { create(:user, account: account, role: :administrator) }
    let(:pipeline) { create_crm_pipeline(account: account, user: admin) }
    let!(:card) do
      account.crm_cards.create!(pipeline: pipeline.first, stage: pipeline.last, title: 'Card',
                                contact: conversation.contact, primary_conversation: conversation, inbox: inbox)
    end

    def responsible(kind)
      query = Crm::Cards::FilterQuery.new(scope: account.crm_cards, params: { responsible_kind: kind.to_s },
                                          conversation_visibility: nil)
      query.send(:apply_responsible_filter, account.crm_cards)
    end

    it 'é o robô atribuído à conversa, mesmo sem robô ligado à caixa' do
      conversation.update!(ai_assignee: bot)

      expect(card.reload.responsible_descriptor).to eq(type: 'bot', id: bot.id, name: 'Ana Maciel')
      expect(responsible(:bot)).to include(card)
      expect(responsible(:none)).not_to include(card)
    end
  end
end
