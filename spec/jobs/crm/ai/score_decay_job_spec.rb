require 'rails_helper'

RSpec.describe Crm::Ai::ScoreDecayJob do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:pipeline) { create_crm_pipeline(account: account, user: admin).first }
  let(:stage) { pipeline.stages.first }

  let(:signals) do
    { 'next_stage_readiness' => 'parcial', 'intent' => 'alta', 'urgency' => 'nenhuma',
      'decision_maker' => 'desconhecido', 'blocker' => 'nenhum', 'last_turn_owner' => 'humano' }
  end

  def enable_score!
    metadata = pipeline.metadata.deep_dup
    metadata['ai'] = (metadata['ai'] || {}).merge('score_enabled' => true)
    pipeline.update!(metadata: metadata)
  end

  def create_card(score:, source: 'ai', status: :open)
    account.crm_cards.create!(
      pipeline: pipeline, stage: stage, title: 'Lead', currency: 'BRL', status: status, score: score,
      metadata: { 'ai' => { 'score' => { 'value' => score, 'source' => source, 'signals' => signals,
                                         'calculated_at' => Time.current.iso8601 } } }
    )
  end

  before { enable_score! }

  # O bug que motivou o job: o decaimento só era aplicado quando havia nova avaliação, e o
  # StaleCardsJob não reavalia card sem atividade nova. Card pontuado alto ficava alto para sempre.
  it 'cools down a silent card without calling the model' do
    card = create_card(score: 45)
    expect(Crm::Ai::EvaluateCardJob).not_to receive(:perform_later)

    travel_to(30.days.from_now) { described_class.perform_now }

    expect(card.reload.score).to be < 45
  end

  it 'zeroes the score of a card that is no longer open' do
    card = create_card(score: 90, status: :won)

    described_class.perform_now

    expect(card.reload.score).to eq(0)
  end

  it 'zeroes closed cards even when legacy metadata no longer passes model validation' do
    card = create_card(score: 90, status: :won)
    card.update_columns(metadata: card.metadata.merge('legacy_note' => 'x' * 1601))

    expect { described_class.perform_now }.not_to raise_error

    expect(card.reload.score).to eq(0)
  end

  it 'never touches a score written by hand' do
    card = create_card(score: 70, source: 'manual')

    travel_to(30.days.from_now) { described_class.perform_now }

    expect(card.reload.score).to eq(70)
  end

  # Achados do review adversarial (codex): o job era o unico escritor sem lock, a ancora de tempo
  # se auto-renovava e cards da versao anterior (sem `signals`) nunca decaiam.
  it 'decays cards scored by the previous version, which have no stored signals' do
    card = account.crm_cards.create!(
      pipeline: pipeline, stage: stage, title: 'Legado', currency: 'BRL', score: 60,
      metadata: { 'ai' => { 'score' => { 'value' => 60, 'source' => 'ai',
                                         'calculated_at' => Time.current.iso8601 } } }
    )

    travel_to(20.days.from_now) { described_class.perform_now }

    expect(card.reload.score).to be < 60
  end

  it 'decays open cards even when unrelated legacy metadata no longer passes model validation' do
    card = create_card(score: 60)
    card.update_columns(metadata: card.metadata.merge('legacy_note' => 'x' * 1601))

    expect do
      travel_to(20.days.from_now) { described_class.perform_now }
    end.not_to raise_error

    expect(card.reload.score).to be < 60
  end

  it 'scopes linked conversation lookup to the card account' do
    card = create_card(score: 60)

    expect(Crm::CardConversation)
      .to receive(:where)
      .with(account_id: [account.id], card_id: [card.id])
      .and_call_original

    travel_to(20.days.from_now) { described_class.perform_now }

    expect(card.reload.score).to be < 60
  end

  it 'uses the cached card last_message_at when there are no linked conversations' do
    card = create_card(score: 60)
    card.update_columns(last_message_at: 20.days.ago)

    expect(Message).not_to receive(:chat)

    described_class.perform_now

    expect(card.reload.score).to be < 60
  end

  it 'keeps processing the batch when one card raises a database error' do
    broken_card = create_card(score: 60)
    healthy_card = create_card(score: 60)
    healthy_card.update_columns(last_message_at: 20.days.ago)

    job = described_class.new
    allow(Rails.logger).to receive(:warn)
    allow(job).to receive(:apply).and_call_original
    allow(job).to receive(:apply).with(broken_card, anything)
                               .and_raise(ActiveRecord::StatementInvalid.new('database error'))

    expect { job.perform }.not_to raise_error

    expect(healthy_card.reload.score).to be < 60
    expect(Rails.logger).to have_received(:warn).with(/ScoreDecayJob.*card_id=#{broken_card.id}.*StatementInvalid/)
  end

  it 'keeps decaying across runs instead of resetting its own clock' do
    card = create_card(score: 50)

    travel_to(10.days.from_now) { described_class.perform_now }
    after_first = card.reload.score
    travel_to(20.days.from_now) { described_class.perform_now }

    expect(card.reload.score).to be < after_first
  end

  it 'skips funnels with the score turned off' do
    metadata = pipeline.metadata.deep_dup
    metadata['ai']['score_enabled'] = false
    pipeline.update!(metadata: metadata)
    card = create_card(score: 45)

    travel_to(30.days.from_now) { described_class.perform_now }

    expect(card.reload.score).to eq(45)
  end
end
