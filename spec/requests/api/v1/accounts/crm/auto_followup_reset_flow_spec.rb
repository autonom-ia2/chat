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

  # O modelo (simulado, sem chamada paga) decide que "SAIR" foi pedido para parar.
  def reply_opt_out(card, conversation)
    opt_out_message = create_incoming_message(conversation: conversation, content: 'SAIR')
    opt_out_message.update!(created_at: 21.hours.ago)
    classifier = instance_double(Crm::Ai::OptOutClassifier, perform: { decision: 'sim', motivo: 'pedido_explicito_de_parar' })
    allow(Crm::Ai::OptOutClassifier).to receive(:new).and_return(classifier)
    perform_enqueued_jobs(only: Crm::FollowUps::OptOutDecisionJob) do
      Crm::FollowUps::AutoFollowupCanceler.new(card: card, message: opt_out_message).maybe_cancel
    end
  end

  # Passo 2: cliente responde "SAIR" — cancelador cancela o toque pendente e o modelo (simulado, sem chamada paga)
  # decide que foi pedido para parar, no OptOutDecisionJob (#1317), que marca opted_out.
  # Data recuada 21h para que, depois do RESET no passo 4, esta mesma mensagem já satisfaça o
  # radar de elegibilidade do planner no passo 5 (last_inbound precisa estar >= 1o intervalo).
  def assert_opt_out_stops_cadence(card, conversation)
    reply_opt_out(card, conversation)

    state = card.reload.metadata['ai']['auto_followup_state']
    expect(state['opted_out']).to be(true)
    expect(state['active']).to be(false)
    expect(card.follow_ups.active.count).to eq(0)
    expect(card.contact.reload.opt_out_source).to eq('follow_up_reply')
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
    expect(card.contact.reload).not_to be_opted_out # chat#1325: o reset libera a recusa follow_up_reply
    assert_sweep_rearms_after_reset(pipeline, card)
  end

  def reset!(account, user, card)
    post "/api/v1/accounts/#{account.id}/crm/cards/#{card.id}/reset_auto_followup", headers: auth_headers(user)
    expect(response).to have_http_status(:ok)
  end

  def other_card(account, user, contact, opted_out:)
    pipeline, stage = create_crm_pipeline(account: account, user: user, name: "Outro funil #{SecureRandom.hex(3)}")
    account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: contact, title: 'Outro assunto',
                              metadata: { 'ai' => { 'auto_followup_state' => { 'opted_out' => opted_out } } })
  end

  # chat#1325: a marca no card é a prova da recusa follow_up_reply. Ela só sai quando nenhum card do contato a sustenta.
  it 'o RESET de um card não libera a recusa que outro card do mesmo contato ainda sustenta' do
    account, user = create_account_and_user
    _pipeline, card_a, conversation = build_stalled_card(account: account, user: user)
    card_a.update!(metadata: { 'ai' => { 'auto_followup_state' => { 'active' => true } } })
    reply_opt_out(card_a, conversation)
    contact = card_a.contact
    expect(contact.reload.opt_out_source).to eq('follow_up_reply')
    card_b = other_card(account, user, contact, opted_out: true)

    reset!(account, user, card_b)
    expect(response.parsed_body['contact_opt_out']).to eq('kept_other_cards')
    expect(contact.reload.opt_out_source).to eq('follow_up_reply')

    reset!(account, user, card_a)
    expect(response.parsed_body['contact_opt_out']).to eq('released')
    expect(contact.reload).not_to be_opted_out
  end

  # Corrida: o "sim" grava o card entre a carga do card pelo controller e o lock do card. O stub do lock! faz esse "sim"
  # chegar logo antes de o lock valer. Com o lock, o reset relê a marca e libera a recusa junto. Sem o lock (só uma
  # transação), o stub não roda; lendo a marca antes do lock, o reset zeraria o card e deixaria a recusa sem prova.
  it 'o RESET lê a marca do card com o card travado' do
    account, user = create_account_and_user
    _pipeline, card, = build_stalled_card(account: account, user: user)
    contact = card.contact
    expect(contact).not_to be_opted_out
    race = { ran: false, contact_opted_out: nil }
    allow_any_instance_of(Crm::Card).to receive(:lock!).and_wrap_original do |original, *args| # rubocop:disable RSpec/AnyInstance
      if original.receiver.id == card.id && !race[:ran]
        race[:ran] = true
        Crm::Card.where(id: card.id).update_all( # rubocop:disable Rails/SkipsModelValidations
          metadata: { 'ai' => { 'auto_followup_state' => { 'opted_out' => true, 'opt_out_contact_id' => contact.id } } }
        )
        contact.opt_out!(source: 'follow_up_reply')
        race[:contact_opted_out] = contact.reload.opt_out_source
      end
      original.call(*args)
    end

    reset!(account, user, card)

    expect(race).to eq(ran: true, contact_opted_out: 'follow_up_reply')
    expect(card.reload.metadata['ai']['auto_followup_state']['opted_out']).to be(false)
    expect(contact.reload).not_to be_opted_out
  end

  it 'card que mudou de contato depois do pedido: o RESET libera o contato marcado, não o atual' do
    account, user = create_account_and_user
    _pipeline, card, = build_stalled_card(account: account, user: user)
    asked = card.contact
    asked.opt_out!(source: 'follow_up_reply')
    newcomer = account.contacts.create!(name: 'Outro', phone_number: '+5511987650001')
    newcomer.opt_out!(source: 'follow_up_reply')
    card.update!(contact: newcomer, primary_conversation: nil,
                 metadata: { 'ai' => { 'auto_followup_state' => { 'opted_out' => true, 'opt_out_contact_id' => asked.id } } })
    expect(Crm::FollowUps::CardOptOut.contact_marked?(asked)).to be(true)

    reset!(account, user, card)

    expect(asked.reload).not_to be_opted_out
    expect(newcomer.reload.opt_out_source).to eq('follow_up_reply')
  end

  it 'o RESET de um card que nunca parou a pedido do cliente não libera nada' do
    account, user = create_account_and_user
    _pipeline, card, = build_stalled_card(account: account, user: user)
    card.contact.opt_out!(source: 'follow_up_reply')

    reset!(account, user, card)

    expect(card.contact.reload.opt_out_source).to eq('follow_up_reply')
  end

  # chat#1325: o reset é dono só da recusa follow_up_reply. A marcada pela equipe continua, e o runner segue parado.
  it 'o RESET não libera a recusa do contato que veio de outra origem' do
    account, user = create_account_and_user
    _pipeline, card, = build_stalled_card(account: account, user: user)
    card.update!(metadata: { 'ai' => { 'auto_followup_state' => { 'opted_out' => true } } })
    card.contact.opt_out!(source: 'manual', by: user)

    post "/api/v1/accounts/#{account.id}/crm/cards/#{card.id}/reset_auto_followup", headers: auth_headers(user)

    expect(response).to have_http_status(:ok)
    contact = card.contact.reload
    expect(contact).to be_opted_out
    expect(contact.opt_out_source).to eq('manual')
    expect(contact.opted_out_by_id).to eq(user.id)
  end
end
