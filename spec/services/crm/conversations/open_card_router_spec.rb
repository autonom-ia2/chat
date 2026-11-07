require 'rails_helper'

# Cliente com card aberto que escreve por outro canal (#1150, R13; decisão do Rodrigo em 12/10): a conversa nova é
# ligada ao card aberto mais recente dele e entregue ao dono, sem passar pela triagem; quem já atende não perde.
RSpec.describe Crm::Conversations::OpenCardRouter do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:dono) { create(:user, account: account, role: :agent, name: 'Léo') }
  let(:outra) { create(:user, account: account, role: :agent, name: 'Ana') }
  let(:whatsapp) { create(:inbox, account: account) }
  let(:email) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:vendas) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let(:contact) { create(:contact, account: account) }
  let!(:card) do
    first = create(:conversation, account: account, inbox: whatsapp, contact: contact, assignee: dono)
    account.crm_cards.create!(pipeline: vendas.first, stage: vendas.last, contact: contact, title: 'Orçamento',
                              primary_conversation: first, inbox: whatsapp, owner: dono, last_activity_at: 2.days.ago)
  end

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  before do
    [dono, outra].each { |user| create(:inbox_member, inbox: email, user: user) }
    account.crm_inbox_settings.create!(inbox: email, crm_enabled: true)
  end

  def nova_conversa(**attrs)
    conversation = create(:conversation, account: account, inbox: email, contact: contact, **attrs)
    create(:message, account: account, inbox: email, conversation: conversation, message_type: :incoming, content: 'Oi')
    conversation
  end

  def linked?(conversation, alvo = card)
    Crm::CardConversation.exists?(card: alvo, conversation: conversation)
  end

  it 'links the new conversation to the open card and hands it to the owner when nobody has replied yet' do
    conversation = nova_conversa(assignee: outra)

    described_class.new(conversation: conversation).perform

    expect(linked?(conversation)).to be(true)
    expect(conversation.reload.assignee_id).to eq(dono.id)
  end

  it 'only links when a person already replied, or when an AI agent is handling the conversation' do
    respondida = nova_conversa(assignee: outra)
    create(:message, account: account, inbox: email, conversation: respondida, message_type: :outgoing, sender: outra)
    described_class.new(conversation: respondida).perform
    expect([linked?(respondida), respondida.reload.assignee_id]).to eq([true, outra.id])

    bot = AgentBot.create!(name: 'Clara', account: account)
    com_ia = nova_conversa
    com_ia.update_columns(assignee_agent_bot_id: bot.id, ai_assignee_type: 'AgentBot') # rubocop:disable Rails/SkipsModelValidations
    described_class.new(conversation: com_ia).perform
    expect([linked?(com_ia), com_ia.reload.assignee_id]).to eq([true, nil])
  end

  it 'only links when the owner is not in the new inbox' do
    email.inbox_members.where(user: dono).destroy_all
    conversation = nova_conversa(assignee: outra)

    described_class.new(conversation: conversation).perform

    expect([linked?(conversation), conversation.reload.assignee_id]).to eq([true, outra.id])
  end

  it 'picks the open card with the latest activity' do
    recente = account.crm_cards.create!(pipeline: vendas.first, stage: vendas.last, contact: contact, title: 'Recente',
                                        inbox: whatsapp, owner: outra, last_activity_at: 1.hour.ago)
    conversation = nova_conversa

    described_class.new(conversation: conversation).perform

    expect([linked?(conversation, recente), linked?(conversation)]).to eq([true, false])
  end

  it 'does nothing for closed cards, old conversations, conversations we started, or conversations with a card' do
    card.update!(status: :archived)
    expect(described_class.new(conversation: nova_conversa).perform).to be_nil

    card.update!(status: :open)
    expect(described_class.new(conversation: nova_conversa(created_at: 2.days.ago)).perform).to be_nil

    campanha = create(:conversation, account: account, inbox: email, contact: contact)
    create(:message, account: account, inbox: email, conversation: campanha, message_type: :outgoing, sender: outra)
    expect(described_class.new(conversation: campanha).perform).to be_nil

    com_card = nova_conversa
    account.crm_cards.create!(pipeline: vendas.first, stage: vendas.last, contact: contact, title: 'Outro',
                              primary_conversation: com_card, inbox: email)
    expect(described_class.new(conversation: com_card).perform).to be_nil
  end

  it 'leaves a card of the same inbox to the usual deduplication' do
    mesmo = account.crm_cards.create!(pipeline: vendas.first, stage: vendas.last, contact: contact, title: 'E-mail',
                                      inbox: email, owner: outra, last_activity_at: 1.minute.ago)
    conversation = nova_conversa

    described_class.new(conversation: conversation).perform

    expect([linked?(conversation, mesmo), linked?(conversation)]).to eq([false, true])
  end

  it 'does nothing when the CRM is off in the new inbox' do
    account.crm_inbox_settings.find_by(inbox: email).update!(crm_enabled: false)
    conversation = nova_conversa

    expect(described_class.new(conversation: conversation).perform).to be_nil
    expect(linked?(conversation)).to be(false)
  end

  it 'is reached from the card sync, which reuses the linked card instead of creating one in an auto-create inbox' do
    account.crm_pipeline_inboxes.create!(inbox: email, pipeline: vendas.first, auto_create_card: true)
    account.crm_inbox_settings.find_by(inbox: email).update!(auto_create_card: true, default_pipeline: vendas.first)
    conversation = nova_conversa

    Crm::Conversations::CardSyncer.new(conversation: conversation).perform
    Crm::Conversations::CardSyncer.new(conversation: conversation).perform

    expect(linked?(conversation)).to be(true)
    expect(account.crm_cards.where(contact: contact).count).to eq(1)
    expect(conversation.reload.assignee_id).to eq(dono.id)
  end
end
