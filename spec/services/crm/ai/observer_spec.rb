require 'rails_helper'

# #1923: a decisão de agendar e o token saem de dentro da trava do card.
RSpec.describe Crm::Ai::Observer do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:card) do
    account.crm_cards.create!(pipeline: pipeline_and_stage.first, stage: pipeline_and_stage.last, title: 'Pedido',
                              contact: create(:contact, account: account))
  end

  before do
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
    clear_enqueued_jobs
  end

  def ai = card.reload.metadata.to_h.fetch('ai', {})

  it 'o token novo é sempre maior que o gravado, mesmo com o relógio de outro processo à frente' do
    adiantado = Time.current.to_f + 60
    described_class.new(card: card).marcar(adiantado)

    token = described_class.new(card: Crm::Card.find(card.id)).schedule_evaluation

    expect(token).to be > adiantado
    expect(ai['evaluate_token']).to eq(token)
  end

  it 'a mensagem da equipe não agenda com uma avaliação esperando a vez, e agenda depois que ela passou' do
    described_class.new(card: card).schedule_evaluation
    clear_enqueued_jobs

    expect(described_class.new(card: Crm::Card.find(card.id)).schedule_evaluation_da_equipe(2.minutes)).to be_nil
    expect(enqueued_jobs).to be_empty

    travel(Crm::Ai::Config::DEBOUNCE_SECONDS.seconds + 1.second) do
      token = described_class.new(card: Crm::Card.find(card.id)).schedule_evaluation_da_equipe(2.minutes)

      expect(enqueued_jobs.map { |job| job['arguments'] }).to eq([[card.id, token, described_class::TRIGGER_DA_EQUIPE]])
    end
  end

  it 'evaluate_after ilegível não derruba quem pergunta' do
    expect(described_class.pendente?({ 'evaluate_after' => 'amanhã' })).to be(false)
    expect(described_class.pendente?({ 'evaluate_after' => '' })).to be(false)
  end
end
