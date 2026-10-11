require 'rails_helper'

RSpec.describe Crm::FollowUps::AutoFollowupCanceler do
  def build_card(account:, user:, active:)
    inbox = create_crm_inbox(account: account, members: [user])
    contact = account.contacts.create!(name: 'Lead', phone_number: "+55119#{rand(10_000_000..99_999_999)}")
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: user)
    pipeline, stage = create_crm_pipeline(account: account, user: user)
    card = account.crm_cards.create!(
      pipeline: pipeline, stage: stage, inbox: inbox, contact: contact,
      primary_conversation: conversation, title: 'Lead'
    )
    card.update!(metadata: { 'ai' => { 'auto_followup_state' => { 'active' => active } } })
    [card, conversation]
  end

  def build_follow_up(account:, card:, conversation:, source:)
    account.crm_follow_ups.create!(
      card: card, conversation: conversation, title: "Toque #{source}", due_at: 1.hour.from_now,
      timezone: 'UTC', automation_mode: :reminder_only, metadata: { 'source' => source }
    )
  end

  def create_outgoing_message(conversation:, content: 'Já te retorno')
    conversation.messages.create!(
      account_id: conversation.account_id, inbox_id: conversation.inbox_id,
      message_type: :outgoing, content: content
    )
  end

  it 'cancela TODOS os follow-ups ai_followup ativos quando o contato responde e grava o state de parada' do
    account, user = create_account_and_user
    card, conversation = build_card(account: account, user: user, active: true)
    touch1 = build_follow_up(account: account, card: card, conversation: conversation, source: 'ai_followup')
    touch2 = build_follow_up(account: account, card: card, conversation: conversation, source: 'ai_followup')
    message = create_incoming_message(conversation: conversation, content: 'Oi, ainda tenho interesse')

    described_class.new(card: card, message: message).maybe_cancel

    expect(touch1.reload.status).to eq('canceled')
    expect(touch2.reload.status).to eq('canceled')
    state = card.reload.metadata['ai']['auto_followup_state']
    expect(state['active']).to be(false)
    expect(state['stopped_reason']).to eq('replied')
    expect(state['opted_out']).to be(false)
  end

  # Risco real de regressão: um retorno manual ou um ai_callback (retorno por data que o próprio
  # cliente pediu) NUNCA pode ser cancelado pela resposta que disparou a cadência genérica.
  it 'NÃO cancela follow-ups de outra origem (manual ou ai_callback) ao processar a resposta' do
    account, user = create_account_and_user
    card, conversation = build_card(account: account, user: user, active: true)
    manual = build_follow_up(account: account, card: card, conversation: conversation, source: 'manual')
    callback = build_follow_up(account: account, card: card, conversation: conversation, source: 'ai_callback')
    message = create_incoming_message(conversation: conversation, content: 'Oi')

    described_class.new(card: card, message: message).maybe_cancel

    expect(manual.reload.status).to eq('pending')
    expect(callback.reload.status).to eq('pending')
  end

  it 'mensagem OUTGOING não cancela nada nem altera o state' do
    account, user = create_account_and_user
    card, conversation = build_card(account: account, user: user, active: true)
    touch = build_follow_up(account: account, card: card, conversation: conversation, source: 'ai_followup')
    message = create_outgoing_message(conversation: conversation)

    described_class.new(card: card, message: message).maybe_cancel

    expect(touch.reload.status).to eq('pending')
    expect(card.reload.metadata['ai']['auto_followup_state']['active']).to be(true)
  end

  it 'cadência inativa (state.active != true) não cancela nada' do
    account, user = create_account_and_user
    card, conversation = build_card(account: account, user: user, active: false)
    touch = build_follow_up(account: account, card: card, conversation: conversation, source: 'ai_followup')
    message = create_incoming_message(conversation: conversation, content: 'Oi')

    described_class.new(card: card, message: message).maybe_cancel

    expect(touch.reload.status).to eq('pending')
  end

  # #1317: o canceler não interpreta o texto. Qualquer resposta para a cadência e fica "pendente" até o modelo dizer,
  # no OptOutDecisionJob, se foi pedido para parar — mesmo "SAIR" não vira opt-out aqui.
  it 'qualquer resposta para a cadência, grava a decisão como pendente e pede a decisão ao modelo' do
    account, user = create_account_and_user
    card, conversation = build_card(account: account, user: user, active: true)
    touch = build_follow_up(account: account, card: card, conversation: conversation, source: 'ai_followup')
    message = create_incoming_message(conversation: conversation, content: 'SAIR')

    expect { described_class.new(card: card, message: message).maybe_cancel }
      .to have_enqueued_job(Crm::FollowUps::OptOutDecisionJob).with(card.id, message.id)

    expect(touch.reload.status).to eq('canceled')
    state = card.reload.metadata['ai']['auto_followup_state']
    expect(state['stopped_reason']).to eq('replied')
    expect(state['opted_out']).to be(false)
    expect(state['opt_out_decision']).to eq('pendente')
    expect(state['stopped_message_id']).to eq(message.id)
  end

  it 'mensagem OUTGOING ou cadência inativa não pede decisão ao modelo' do
    account, user = create_account_and_user
    card, conversation = build_card(account: account, user: user, active: true)
    inactive_card, inactive_conversation = build_card(account: account, user: user, active: false)

    expect do
      described_class.new(card: card, message: create_outgoing_message(conversation: conversation)).maybe_cancel
      described_class.new(card: inactive_card, message: create_incoming_message(conversation: inactive_conversation)).maybe_cancel
    end.not_to have_enqueued_job(Crm::FollowUps::OptOutDecisionJob)
  end

  it 'registra a atividade ai_followup_stopped com o motivo do cancelamento' do
    account, user = create_account_and_user
    card, conversation = build_card(account: account, user: user, active: true)
    build_follow_up(account: account, card: card, conversation: conversation, source: 'ai_followup')
    message = create_incoming_message(conversation: conversation, content: 'Oi')

    described_class.new(card: card, message: message).maybe_cancel

    activity = card.activities.find_by(event_type: 'ai_followup_stopped')
    expect(activity).to be_present
    expect(activity.payload['reason']).to eq('replied')
    expect(activity.payload['trigger']).to eq('inbound_reply')
  end

  it 'mensagem incoming sem conteúdo (nil) cancela a cadência como reply comum, sem estourar erro' do
    account, user = create_account_and_user
    card, conversation = build_card(account: account, user: user, active: true)
    touch = build_follow_up(account: account, card: card, conversation: conversation, source: 'ai_followup')
    message = conversation.messages.create!(
      account_id: conversation.account_id, inbox_id: conversation.inbox_id,
      message_type: :incoming, content: nil, sender: conversation.contact
    )

    expect { described_class.new(card: card, message: message).maybe_cancel }.not_to raise_error

    expect(touch.reload.status).to eq('canceled')
    expect(card.reload.metadata['ai']['auto_followup_state']['stopped_reason']).to eq('replied')
  end
end
