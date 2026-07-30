require 'rails_helper'

RSpec.describe Crm::Ai::ScoreApplier do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:pipeline) { create_crm_pipeline(account: account, user: admin).first }
  let(:stage) { pipeline.stages.first }
  let(:card) do
    account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Lead', currency: 'BRL')
  end

  let(:signals) do
    {
      next_stage_readiness: 'pronta', intent: 'alta', urgency: 'imediata',
      decision_maker: 'sim', blocker: 'nenhum', last_turn_owner: 'cliente',
      unfulfilled_promise: false, unreadable: false, reason: 'Pediu link de pagamento'
    }
  end

  def enable_score!
    metadata = pipeline.metadata.deep_dup
    metadata['ai'] = (metadata['ai'] || {}).merge('score_enabled' => true)
    pipeline.update!(metadata: metadata)
  end

  it 'writes nothing while the funnel has the score turned off' do
    described_class.new(card: card, signals: signals).perform

    expect(card.reload.score).to eq(0)
    expect(card.metadata.dig('ai', 'score')).to be_nil
  end

  it 'writes score, tier and reason once the funnel enables it' do
    enable_score!

    described_class.new(card: card, signals: signals).perform
    card.reload

    expect(card.score).to be > 0
    expect(card.metadata.dig('ai', 'score')).to include(
      'tier' => 'urgente',
      'reason' => 'Pediu link de pagamento',
      'source' => 'ai',
      'stage_id' => stage.id
    )
  end

  it 'does not overwrite a manual score while the card stays in the same stage' do
    enable_score!
    metadata = card.metadata.deep_dup
    metadata['ai'] = { 'score' => { 'value' => 20, 'source' => 'manual', 'stage_id' => stage.id } }
    card.update!(score: 20, metadata: metadata)

    described_class.new(card: card, signals: signals).perform

    expect(card.reload.score).to eq(20)
  end

  it 'takes the score back over after the card moves to another stage' do
    enable_score!
    other_stage = pipeline.stages.create!(account: account, name: 'Proposta', position: 2)
    metadata = card.metadata.deep_dup
    metadata['ai'] = { 'score' => { 'value' => 20, 'source' => 'manual', 'stage_id' => stage.id } }
    card.update!(score: 20, metadata: metadata, stage: other_stage)

    described_class.new(card: card, signals: signals).perform

    expect(card.reload.score).not_to eq(20)
    expect(card.metadata.dig('ai', 'score', 'source')).to eq('ai')
  end
end
