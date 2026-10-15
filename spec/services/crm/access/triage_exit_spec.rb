require 'rails_helper'

# Saída da triagem e participantes (#1150, R10; decisão do Rodrigo em 12/10). Quando nasce o primeiro card, a conversa
# vai para quem tem o funil dele: quem atendia só na triagem (sem o funil) sai, e o rodízio do funil escolhe. Card
# novo depois disso não transfere: o dono entra como participante. Sem acesso por funil na conta, nada muda.
RSpec.describe 'Acesso por funil: saída da triagem' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:triagem) { create(:user, account: account, role: :agent, name: 'Ana triagem') }
  let(:vendas_agent) { create(:user, account: account, role: :agent, name: 'Léo vendas') }
  let(:pos_agent) { create(:user, account: account, role: :agent, name: 'Paula pós-venda') }
  let(:propria) { create(:user, account: account, role: :agent, name: 'Carla só as suas') }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:vendas) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let(:pos_venda) { create_crm_pipeline(account: account, user: admin, name: 'Pós-venda') }
  let(:contact) { create(:contact, account: account) }

  before do
    [triagem, vendas_agent, pos_agent, propria].each { |user| create(:inbox_member, inbox: inbox, user: user) }
    access(triagem, triage: true)
    access(vendas_agent, vendas)
    access(pos_agent, pos_venda)
    access(propria, vendas, only_own: true)
  end

  def access(user, funnel = nil, triage: false, only_own: false)
    row = Crm::InboxAgentAccess.create!(account: account, inbox: inbox, user: user, all_pipelines: false,
                                        triage: triage, only_own: only_own)
    row.agent_pipelines.create!(account: account, pipeline: funnel.first) if funnel
  end

  def conversation_with(assignee)
    create(:conversation, account: account, inbox: inbox, contact: contact, assignee: assignee)
  end

  def card_in(conversation, (pipeline, stage), owner: nil)
    account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: contact, title: pipeline.name,
                              primary_conversation: conversation, inbox: inbox, owner: owner)
  end

  def sync(conversation)
    Crm::Access::VisibilitySync.perform(conversation.reload)
    conversation.reload
  end

  it 'takes the conversation away from the triage person when the first card is born in a funnel she does not have' do
    conversation = conversation_with(triagem)
    card = card_in(conversation, vendas, owner: triagem)

    sync(conversation)

    expect(conversation.assignee_id).to be_nil
    expect(card.reload.owner_id).to be_nil
    expect(conversation.conversation_participants.where(user_id: triagem.id)).to be_empty
  end

  it 'hands the conversation to the funnel round-robin when the inbox assigns automatically' do
    inbox.update!(enable_auto_assignment: true)
    allow(OnlineStatusTracker).to receive(:get_available_users)
      .and_return([triagem, vendas_agent, pos_agent, propria].to_h { |user| [user.id.to_s, 'online'] })
    conversation = conversation_with(triagem)
    card_in(conversation, vendas, owner: triagem)

    sync(conversation)

    expect(conversation.assignee_id).to eq(vendas_agent.id)
  end

  it 'end to end: the card is born, the jobs run, someone with the funnel gets the conversation and the card, and it stops' do
    inbox.update!(enable_auto_assignment: true)
    allow(OnlineStatusTracker).to receive(:get_available_users)
      .and_return([triagem, vendas_agent, pos_agent, propria].to_h { |user| [user.id.to_s, 'online'] })
    allow(Crm::Access::VisibilitySync).to receive(:perform).and_call_original
    conversation = conversation_with(triagem)

    card = with_modified_env(CRM_KANBAN_ENABLED: 'true') do
      perform_enqueued_jobs { card_in(conversation, vendas, owner: triagem) }
    end

    expect(conversation.reload.assignee_id).to eq(vendas_agent.id)
    expect(card.reload.owner_id).to eq(vendas_agent.id)
    # O card nascer agenda uma sincronização; o vínculo card↔conversa que o CardSyncer cria agenda a segunda. Com alguém
    # em "Só as suas" na caixa, o dono também decide quem vê (#1652): a saída da triagem tira o dono (terceira) e o
    # CardSyncer põe o novo atendente como dono (quarta), que já não muda nada. O perform_enqueued_jobs roda a fila até
    # esvaziar: exatamente quatro prova que não há quinta e a cadeia termina.
    expect(Crm::Access::VisibilitySync).to have_received(:perform).exactly(4).times
  end

  it 'keeps the conversation with whoever already has the funnel of the card' do
    conversation = conversation_with(vendas_agent)
    card_in(conversation, vendas, owner: vendas_agent)

    sync(conversation)

    expect(conversation.assignee_id).to eq(vendas_agent.id)
  end

  it 'keeps the conversation with someone on "only theirs"' do
    conversation = conversation_with(propria)
    card_in(conversation, pos_venda)

    sync(conversation)

    expect(conversation.assignee_id).to eq(propria.id)
  end

  it 'does not transfer on a later card: its owner joins as participant' do
    conversation = conversation_with(vendas_agent)
    card_in(conversation, vendas, owner: vendas_agent)
    card_in(conversation, pos_venda, owner: pos_agent)

    sync(conversation)

    expect(conversation.assignee_id).to eq(vendas_agent.id)
    expect(conversation.conversation_participants.pluck(:user_id)).to include(pos_agent.id)
  end

  it 'does not make a participant of an owner without the funnel, nor of an administrator outside the inbox' do
    conversation = conversation_with(vendas_agent)
    card_in(conversation, vendas, owner: vendas_agent)
    card_in(conversation, pos_venda, owner: vendas_agent)
    card_in(conversation, pos_venda, owner: admin)

    sync(conversation)

    expect(conversation.assignee_id).to eq(vendas_agent.id)
    expect(conversation.conversation_participants.pluck(:user_id)).not_to include(admin.id)
  end

  it 'does nothing in an inbox without access rows, even with rows elsewhere in the account' do
    other_inbox = create(:inbox, account: account, enable_auto_assignment: false)
    create(:inbox_member, inbox: other_inbox, user: triagem)
    create(:inbox_member, inbox: other_inbox, user: pos_agent)
    conversation = create(:conversation, account: account, inbox: other_inbox, contact: contact, assignee: triagem)
    account.crm_cards.create!(pipeline: vendas.first, stage: vendas.last, contact: contact, title: 'Vendas',
                              primary_conversation: conversation, inbox: other_inbox, owner: triagem)
    account.crm_cards.create!(pipeline: pos_venda.first, stage: pos_venda.last, contact: contact, title: 'Pós',
                              primary_conversation: conversation, inbox: other_inbox, owner: pos_agent)

    sync(conversation)

    expect(conversation.assignee_id).to eq(triagem.id)
    expect(conversation.conversation_participants.pluck(:user_id)).not_to include(pos_agent.id)
  end

  it 'changes nothing when the account has no access rows' do
    Crm::InboxAgentAccess.where(account: account).destroy_all
    conversation = conversation_with(triagem)
    card_in(conversation, vendas, owner: triagem)

    sync(conversation)

    expect(conversation.assignee_id).to eq(triagem.id)
  end

  describe 'em caixa com robô (#1377)' do
    let(:bot) { create(:agent_bot, account: account) }

    before { create(:agent_bot_inbox, inbox: inbox, agent_bot: bot) }

    it 'devolve a conversa ao robô, à espera do rodízio do funil' do
      conversation = conversation_with(triagem)
      card_in(conversation, vendas, owner: triagem)

      sync(conversation)

      expect(conversation).to have_attributes(assignee_id: nil, ai_assignee: bot, status: 'open')
      expect(conversation).to be_bot_handoff_waiting
      expect(Conversation.awaiting_person).to include(conversation)
    end

    it 'a resposta do robô depois da saída não tira a conversa do rodízio' do
      conversation = conversation_with(triagem)
      card_in(conversation, vendas, owner: triagem)
      sync(conversation)

      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: bot, content: 'Oi')

      expect(Conversation.awaiting_person).to include(conversation.reload)
    end

    %i[resolved snoozed].each do |status|
      it "devolve ao robô sem reabrir nem esperar rodízio uma conversa #{status}" do
        conversation = conversation_with(triagem)
        conversation.update!(status: status, snoozed_until: (1.day.from_now if status == :snoozed))
        card_in(conversation, vendas, owner: triagem)

        sync(conversation)

        expect(conversation).to have_attributes(assignee_id: nil, ai_assignee: bot, status: status.to_s)
        expect(conversation).not_to be_bot_handoff_waiting
      end
    end

    it 'com rodízio na caixa, quem tem o funil recebe a conversa e o robô sai' do
      inbox.update!(enable_auto_assignment: true)
      allow(OnlineStatusTracker).to receive(:get_available_users)
        .and_return([triagem, vendas_agent, pos_agent, propria].to_h { |user| [user.id.to_s, 'online'] })
      conversation = conversation_with(triagem)
      card_in(conversation, vendas, owner: triagem)

      sync(conversation)

      expect(conversation).to have_attributes(assignee_id: vendas_agent.id, ai_assignee: nil)
      expect(conversation).not_to be_bot_handoff_waiting
    end
  end
end
