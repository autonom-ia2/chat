require 'rails_helper'

# Regressão de ponta a ponta do fluxo completo: cliente pede para SAIR -> cancelador marca
# opt_out -> varredura do planner NÃO re-arma -> humano faz RESET manual pelo endpoint do drawer
# -> card volta a ser elegível pela varredura seguinte. Cobre a integração entre
# AutoFollowupCanceler, AutoFollowupPlanner e Api::V1::Accounts::Crm::CardsController#reset_auto_followup
# que nenhum spec unitário isolado prova sozinho.
RSpec.describe 'CRM auto follow-up opt-out + manual reset regression flow', type: :request do
  around do |example|
    previous_crm = ENV.fetch('CRM_KANBAN_ENABLED', nil)
    previous_ai = ENV.fetch('CRM_AI_ENABLED', nil)
    ENV['CRM_KANBAN_ENABLED'] = 'true'
    ENV['CRM_AI_ENABLED'] = 'true'
    example.run
  ensure
    previous_crm.nil? ? ENV.delete('CRM_KANBAN_ENABLED') : ENV['CRM_KANBAN_ENABLED'] = previous_crm
    previous_ai.nil? ? ENV.delete('CRM_AI_ENABLED') : ENV['CRM_AI_ENABLED'] = previous_ai
  end

  def eligible_config
    { 'enabled' => true, 'intervals_hours' => [20, 72, 168], 'max_touches' => 3,
      'quiet_hours' => { 'start' => 0, 'end' => 24 } }
  end

  def build_stalled_card(account:, user:)
    pipeline, stage = create_crm_pipeline(account: account, user: user)
    pipeline.update!(metadata: { 'ai' => { 'auto_followup' => eligible_config } })
    inbox = create_crm_whatsapp_api_inbox(account: account, members: [user])
    contact = account.contacts.create!(name: 'Lead', phone_number: '+5511987654399')
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: user)
    2.times { create_incoming_message(conversation: conversation) }
    2.times { conversation.messages.create!(account_id: account.id, inbox_id: inbox.id, message_type: :outgoing, content: 'Oi') }
    # A âncora da cadência é a ÚLTIMA mensagem da conversa (CadenceAnchor), de quem quer que seja:
    # envelhecer só a última do cliente deixaria a saída do time em "agora" e o card nunca ficaria
    # elegível.
    conversation.messages.each { |message| message.update!(created_at: 21.hours.ago) }
    card = account.crm_cards.create!(
      pipeline: pipeline, stage: stage, inbox: inbox, contact: contact,
      primary_conversation: conversation, title: 'Lead'
    )
    [pipeline, card, conversation]
  end

  # Passo 1: primeira varredura arma o toque 1 normalmente.
  def assert_first_touch_planned(pipeline, card)
    expect(Crm::FollowUps::AutoFollowupPlanner.new(pipeline: pipeline).perform).to eq(1)
    expect(card.reload.metadata['ai']['auto_followup_state']['active']).to be(true)
  end

  # Passo 2: cliente responde "SAIR" — cancelador cancela o toque pendente e marca opted_out.
  # Data recuada 21h para que, depois do RESET no passo 4, esta mesma mensagem já satisfaça o
  # radar de elegibilidade do planner no passo 5 (last_inbound precisa estar >= 1o intervalo).
  def assert_opt_out_stops_cadence(card, conversation)
    opt_out_message = create_incoming_message(conversation: conversation, content: 'SAIR')
    opt_out_message.update!(created_at: 21.hours.ago)
    Crm::FollowUps::AutoFollowupCanceler.new(card: card, message: opt_out_message).maybe_cancel

    state = card.reload.metadata['ai']['auto_followup_state']
    expect(state['opted_out']).to be(true)
    expect(state['active']).to be(false)
    expect(card.follow_ups.active.count).to eq(0)
  end

  # Passo 3: varredura seguinte NÃO re-arma o card opted_out (guard `opted_out?`). follow_ups.count
  # continua 1 (o touch #1 cancelado no passo 2 permanece no histórico); .active.count == 0 prova
  # que nada novo foi criado.
  def assert_sweep_does_not_rearm(pipeline, card)
    expect(Crm::FollowUps::AutoFollowupPlanner.new(pipeline: pipeline).perform).to eq(0)
    expect(card.reload.follow_ups.active.count).to eq(0)
    expect(card.metadata['ai']['auto_followup_state']['opted_out']).to be(true)
  end

  # Passo 4: humano faz RESET manual pelo endpoint do drawer.
  def assert_manual_reset_clears_state(account, user, card)
    post "/api/v1/accounts/#{account.id}/crm/cards/#{card.id}/reset_auto_followup", headers: auth_headers(user)

    expect(response).to have_http_status(:ok)
    state = card.reload.metadata['ai']['auto_followup_state']
    expect(state['opted_out']).to be(false)
    expect(state['active']).to be(false)
    expect(card.activities.find_by(event_type: 'ai_followup_reset')).to be_present
  end

  # Passo 5: depois do reset, a varredura volta a considerar o card elegível. follow_ups.active.sole
  # (não .sole puro) porque o touch #1 cancelado no passo 2 continua no histórico do card.
  def assert_sweep_rearms_after_reset(pipeline, card)
    expect(Crm::FollowUps::AutoFollowupPlanner.new(pipeline: pipeline).perform).to eq(1)
    follow_up = card.reload.follow_ups.active.sole
    expect(follow_up.metadata['source']).to eq('ai_followup')
    expect(card.metadata['ai']['auto_followup_state']['active']).to be(true)
  end

  it 'card que respondeu SAIR não é re-armado pela varredura até o RESET manual, e depois volta a ser elegível' do
    account, user = create_account_and_user
    pipeline, card, conversation = build_stalled_card(account: account, user: user)

    assert_first_touch_planned(pipeline, card)
    assert_opt_out_stops_cadence(card, conversation)
    assert_sweep_does_not_rearm(pipeline, card)
    assert_manual_reset_clears_state(account, user, card)
    assert_sweep_rearms_after_reset(pipeline, card)
  end
end
