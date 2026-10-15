require 'rails_helper'

# Prazo do próprio card no futuro (chat#1522, decisão do Rodrigo em 14/10/2026): num funil de Atender, a recusa por
# "não há o que enviar agora" não encerra a cadência; o toque espera até 1 dia depois do `expected_close_at`, uma vez por
# card, sem consumir o toque.
RSpec.describe Crm::FollowUps::AutoFollowupRunner do
  let(:now) { Time.utc(2026, 10, 14, 15) }
  let(:refusal) do
    { 'should_send' => false, 'closure_detected' => false, 'confidence' => 0.9, 'decline_reason' => 'nothing_to_send',
      'chosen_template' => { 'index' => -1 }, 'template_variables' => {} }
  end

  before do
    travel_to now
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
  end

  def setup_card(counts_as_sale:, expected_close_at:)
    account, user = create_account_and_user
    inbox = create_crm_whatsapp_api_inbox(account: account, members: [user])
    inbox.channel.enable_whatsapp_api_campaigns!(provider: 'cloud')
    contact = account.contacts.create!(name: 'Cliente', phone_number: '+5511987654321')
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: user)
    create_incoming_message(conversation: conversation)
    conversation.messages.incoming.last.update!(created_at: 30.hours.ago)
    pipeline, stage = create_crm_pipeline(account: account, user: user)
    pipeline.update!(counts_as_sale: counts_as_sale, metadata: { ai: { auto_followup: { enabled: true } } })
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, inbox: inbox, contact: contact, title: 'Cobrança',
                                     primary_conversation: conversation, expected_close_at: expected_close_at)
    follow_up = account.crm_follow_ups.create!(
      card: card, conversation: conversation, contact: contact, title: 'Retornar', due_at: 10.minutes.ago, timezone: 'UTC',
      automation_mode: :auto_send_message, created_by: user,
      metadata: { 'source' => 'ai_followup', 'touch' => 1, 'message_body' => 'rascunho' }
    )
    [card, follow_up]
  end

  def run(follow_up, composition = refusal, at: now)
    runner = described_class.new(follow_up: follow_up, now: at)
    allow(runner).to receive_messages(compose: composition, template_candidates: [])
    runner.perform
  end

  def state(card)
    card.reload.metadata.to_h.dig('ai', 'auto_followup_state').to_h
  end

  context 'with a serve pipeline and a due date in the future' do
    let(:due_day) { Time.utc(2026, 10, 20) }

    it 'waits until the day after the due date instead of ending the cadence' do
      card, follow_up = setup_card(counts_as_sale: false, expected_close_at: due_day)

      result = run(follow_up)

      expect(result.status).to eq(:rescheduled)
      expect(follow_up.reload.status).to eq('pending')
      expect(follow_up.due_at).to eq(Time.utc(2026, 10, 21, 11)) # 08:00 em São Paulo, primeiro horário permitido do dia 21
      expect(state(card)).to include('deadline_wait_done' => true)
      expect(state(card)['spent']).not_to be(true)
      expect(card.reload.metadata.to_h.dig('ai', 'auto_followup_state', 'stopped_reason')).to be_nil
    end

    it 'does not consume the touch: the same touch runs again after the date' do
      card, follow_up = setup_card(counts_as_sale: false, expected_close_at: due_day)

      run(follow_up)

      expect(follow_up.reload.metadata['touch']).to eq(1)
      expect(follow_up.account.crm_follow_ups.where(card: card).count).to eq(1) # nenhum toque 2 criado
      expect(follow_up).to be_pending
    end

    it 'still waits when the due date is today: only a past date ends the cadence' do
      card, follow_up = setup_card(counts_as_sale: false, expected_close_at: Time.utc(2026, 10, 14))

      result = run(follow_up)

      expect(result.status).to eq(:rescheduled)
      expect(follow_up.reload.due_at).to eq(Time.utc(2026, 10, 15, 11))
      expect(state(card)).to include('deadline_wait_done' => true)
    end

    it 'waits only once per card: a second refusal ends the cadence as before' do
      card, follow_up = setup_card(counts_as_sale: false, expected_close_at: due_day)
      run(follow_up)
      follow_up.update!(due_at: 1.minute.ago)

      result = run(follow_up.reload)

      expect(result.status).to eq(:skipped)
      expect(state(card)).to include('spent' => true, 'stopped_reason' => 'no_open_loop')
    end

    it 'ends the cadence once the due date has passed' do
      card, follow_up = setup_card(counts_as_sale: false, expected_close_at: Time.utc(2026, 10, 10))

      result = run(follow_up)

      expect(result.status).to eq(:skipped)
      expect(state(card)).to include('spent' => true, 'stopped_reason' => 'no_open_loop')
    end
  end

  it 'keeps ending the cadence in a sales pipeline, even with a due date in the future' do
    card, follow_up = setup_card(counts_as_sale: true, expected_close_at: Time.utc(2026, 10, 20))

    result = run(follow_up)

    expect(result.status).to eq(:skipped)
    expect(state(card)).to include('spent' => true, 'stopped_reason' => 'no_open_loop')
  end

  it 'keeps ending the cadence when the card has no due date' do
    card, follow_up = setup_card(counts_as_sale: false, expected_close_at: nil)

    result = run(follow_up)

    expect(result.status).to eq(:skipped)
    expect(state(card)).to include('spent' => true)
  end

  it 'does not wait for a low-confidence send: that is not a refusal on merit' do
    card, follow_up = setup_card(counts_as_sale: false, expected_close_at: Time.utc(2026, 10, 20))
    # `nothing_to_send` mantido de propósito: sem ele o skip vira `no_template` e o teste não chega no guarda de `should_send`.
    low = refusal.merge('should_send' => true, 'confidence' => 0.1)

    result = run(follow_up, low)

    expect(result.status).to eq(:skipped)
    expect(state(card)).to include('spent' => true)
  end

  it 'does not wait when the conversation was closed: closure still stops the cadence' do
    card, follow_up = setup_card(counts_as_sale: false, expected_close_at: Time.utc(2026, 10, 20))

    result = run(follow_up, refusal.merge('closure_detected' => true))

    expect(result.status).to eq(:skipped)
    expect(state(card)).to include('spent' => true, 'stopped_reason' => 'conversation_closed')
  end
end
