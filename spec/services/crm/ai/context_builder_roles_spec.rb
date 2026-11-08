require 'rails_helper'

RSpec.describe Crm::Ai::ContextBuilder do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:pipeline) { create_crm_pipeline(account: account, user: admin).first }
  let(:stage) { pipeline.stages.first }
  let(:inbox) { create_crm_inbox(account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create_crm_conversation(account: account, inbox: inbox, contact: contact) }
  let(:card) do
    account.crm_cards.create!(
      pipeline: pipeline,
      stage: stage,
      title: 'Lead',
      contact: contact,
      primary_conversation: conversation,
      currency: 'BRL'
    )
  end

  def add_message(content:, type:, sender: nil, target: nil)
    create(
      :message,
      account: account,
      inbox: inbox,
      conversation: target || conversation,
      content: content,
      message_type: type,
      sender: sender
    )
  end

  it 'distinguishes customer, human agent, platform agent and external agent' do
    platform_bot = create(:agent_bot, account: account)
    external_bot = create(:agent_bot, account: account)
    Autonomia::Agents::AgentInbox.create!(
      account: account,
      agent: Autonomia::Agents::Agent.create!(account: account, name: 'Agente', agent_type: 'sdr'),
      inbox: inbox,
      agent_bot: platform_bot
    )

    add_message(content: 'quero cotar', type: :incoming, sender: contact)
    add_message(content: 'te ajudo agora', type: :outgoing, sender: admin)
    add_message(content: 'segue a proposta', type: :outgoing, sender: platform_bot)
    add_message(content: 'integracao externa', type: :outgoing, sender: external_bot)

    roles = described_class.new(card: card).perform[:recent_messages].map { |m| m[:role] }

    expect(roles).to eq(%w[customer human_agent platform_agent external_agent])
  end

  # #1601: o convite e o aviso do Agendamento saem em nome da pessoa, mas quem manda é a plataforma; o que a equipe
  # manda pelo celular volta como eco sem remetente e é uma pessoa do time, não um robô de fora.
  it 'labels booking notices as the platform agent and the phone echo as a human agent' do
    aviso = add_message(content: 'Lembrete: sua reunião é amanhã', type: :outgoing, sender: admin)
    aviso.update!(content_attributes: { 'crm_booking_notice' => 'lembrete_1d' })
    convite = add_message(content: 'Escolha um horário', type: :outgoing, sender: admin)
    convite.update!(content_attributes: { 'crm_booking_invite_id' => 7 })
    eco = add_message(content: 'Te ligo em 5 min', type: :outgoing)
    eco.update_columns(sender_type: nil, sender_id: nil, content_attributes: { 'external_echo' => true }) # rubocop:disable Rails/SkipsModelValidations
    automacao = add_message(content: 'Mensagem da automação', type: :outgoing)
    automacao.update_columns(sender_type: nil, sender_id: nil) # rubocop:disable Rails/SkipsModelValidations

    roles = described_class.new(card: card).perform[:recent_messages].map { |m| m[:role] }

    expect(roles).to eq(%w[platform_agent platform_agent human_agent external_agent])
    expect(described_class.new(card: card).perform.dig(:conversation_state, :last_human_agent_at)).to eq(eco.reload.created_at.iso8601)
  end

  it 'reads messages from linked conversations, not only the primary one' do
    other = create_crm_conversation(account: account, inbox: inbox, contact: contact)
    card.card_conversations.create!(account: account, conversation: other)

    add_message(content: 'primeira conversa', type: :incoming, sender: contact)
    add_message(content: 'segunda conversa', type: :incoming, sender: contact, target: other)

    messages = described_class.new(card: card).perform[:recent_messages]

    expect(messages.map { |m| m[:content] }).to contain_exactly('primeira conversa', 'segunda conversa')
    expect(messages.map { |m| m[:conversation_id] }).to contain_exactly(conversation.id, other.id)
  end

  # Sem isto o follow-up anterior da IA volta como 'human_agent' (ele é entregue em nome do
  # responsável) e o cérebro entende que uma pessoa do time perguntou algo e ficou sem resposta.
  it 'labels a previous auto follow-up as the platform agent, not as a human' do
    sent = add_message(content: 'conseguiu acessar o questionário?', type: :outgoing, sender: admin)
    sent.update!(content_attributes: { 'crm_follow_up_id' => 1 })
    add_message(content: 'resposta humana de verdade', type: :outgoing, sender: admin)

    roles = described_class.new(card: card).perform[:recent_messages].map { |m| m[:role] }

    expect(roles).to eq(%w[platform_agent human_agent])
  end

  it 'exposes who is handling the conversation now' do
    conversation.update!(assignee: admin, status: :open)
    add_message(content: 'vou aguardar', type: :incoming, sender: contact)
    human_message = add_message(content: 'te retorno com o orcamento', type: :outgoing, sender: admin)
    add_message(content: 'mensagem de bot', type: :outgoing, sender: create(:agent_bot, account: account))

    state = described_class.new(card: card).perform[:conversation_state]

    expect(state[:status]).to eq('open')
    expect(state[:assigned_to_human]).to be(true)
    expect(state[:last_human_agent_at]).to eq(human_message.created_at.iso8601)
  end

  # O follow-up sai com sender_type 'User'. Se ele contasse como fala humana, cada toque da IA
  # renovaria o relógio e a conversa pareceria estar sendo conduzida por uma pessoa.
  #
  # Horários DISTINTOS de propósito: com tudo nascendo no mesmo segundo, o iso8601 da fala humana e
  # o do toque da IA ficam iguais e este teste passa mesmo com o descarte quebrado — foi assim que
  # um filtro SQL que nunca excluiu nada chegou a produção.
  it 'ignores its own follow-up and private notes when timing the last human reply' do
    conversation.update!(assignee: admin)
    human_message = add_message(content: 'te retorno com o orcamento', type: :outgoing, sender: admin)
    human_message.update!(created_at: 3.hours.ago)
    add_message(content: 'nota interna', type: :outgoing, sender: admin)
      .update!(private: true, created_at: 2.hours.ago)
    add_message(content: 'follow-up automatico', type: :outgoing, sender: admin)
      .update!(content_attributes: { 'crm_follow_up_id' => 1 }, created_at: 1.hour.ago)

    state = described_class.new(card: card).perform[:conversation_state]

    expect(state[:last_human_agent_at]).to eq(human_message.reload.created_at.iso8601)
  end

  # #1923: a falha do envio chega depois (message_updated), com a avaliação já agendada. O que não chegou ao cliente
  # não vai ao modelo nem conta como a última fala da equipe.
  it 'leaves a failed send out of the history and of the last human reply' do
    add_message(content: 'quero cotar', type: :incoming, sender: contact)
    entregue = add_message(content: 'já te mando', type: :outgoing, sender: admin)
    entregue.update_columns(status: nil) # rubocop:disable Rails/SkipsModelValidations -- linha antiga, sem status
    travel(1.minute) { add_message(content: 'segue a cotação: R$ 1.200', type: :outgoing, sender: admin).update!(status: :failed) }

    context = described_class.new(card: card).perform

    expect(context[:recent_messages].pluck(:content)).to eq(['quero cotar', 'já te mando'])
    expect(context[:conversation_state][:last_human_agent_at]).to eq(entregue.reload.created_at.iso8601)
  end
end
