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
      decision_maker: 'sim', blocker: 'nenhum', ready_to_close: 'nao_se_aplica', buying_signal: true,
      unfulfilled_promise: false, unreadable: false, reason: 'Pediu link de pagamento'
    }
  end

  def enable_score!
    metadata = pipeline.metadata.deep_dup
    metadata['ai'] = (metadata['ai'] || {}).merge('score_enabled' => true)
    pipeline.update!(metadata: metadata)
  end

  it 'writes nothing while the funnel has the score turned off' do
    pipeline.update!(metadata: pipeline.metadata.deep_merge('ai' => { 'score_enabled' => false }))
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

  # #1962: quem espera vem do banco. Mesmos sinais fracos; muda só quem mandou a última mensagem real.
  describe 'cliente esperando, lido do banco' do
    let(:inbox) { create_crm_inbox(account: account, members: [admin]) }
    let(:conversation) do
      contact = account.contacts.create!(name: 'Lead', phone_number: '+5511988887777')
      create_crm_conversation(account: account, inbox: inbox, contact: contact)
    end
    let(:weak_signals) do
      { next_stage_readiness: 'inicial', intent: 'baixa', urgency: 'nenhuma', decision_maker: 'desconhecido',
        blocker: 'nenhum', ready_to_close: 'nao_se_aplica', buying_signal: false, unfulfilled_promise: false,
        unreadable: false, reason: 'Cliente perguntou e ninguém respondeu' }
    end

    def message(type, at)
      conversation.messages.create!(account: account, inbox: inbox, content: 'x', message_type: type, created_at: at,
                                    sender: type == :incoming ? conversation.contact : admin)
    end

    before do
      enable_score!
      card.update!(conversation_id: conversation.id)
    end

    it 'segura no piso de quente quando o cliente falou por último' do
      message(:outgoing, 6.days.ago)
      message(:incoming, 5.days.ago)

      described_class.new(card: card, signals: weak_signals).perform

      expect(card.reload.metadata.dig('ai', 'score', 'tier')).to eq('quente')
      expect(card.metadata.dig('ai', 'score', 'breakdown', 'customer_waiting')).to be > 0
    end

    it 'deixa esfriar quando nós respondemos por último' do
      message(:incoming, 6.days.ago)
      message(:outgoing, 5.days.ago)

      described_class.new(card: card, signals: weak_signals).perform

      expect(card.reload.metadata.dig('ai', 'score', 'tier')).to eq('frio')
    end
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
