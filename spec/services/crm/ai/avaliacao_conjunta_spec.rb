require 'rails_helper'

# #1693: as bordas da avaliação conjunta, com a IA do CRM simulada.
RSpec.describe Crm::Ai::AvaliacaoConjunta do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:pipeline_e_etapa) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let(:cliente) { instance_double(Crm::Ai::ResponsesClient) }
  let(:auto) { criar_card('Seguro auto') }
  let(:residencial) { criar_card('Seguro residencial') }

  before do
    allow(Crm::Ai::Config).to receive_messages(enabled?: true, media_enabled?: false)
    allow(Crm::Ai::CredentialResolver).to receive(:new)
      .and_return(instance_double(Crm::Ai::CredentialResolver, configured?: true, resolve: { api_key: 'k' }))
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente)
  end

  def criar_card(titulo)
    pipeline, etapa = pipeline_e_etapa
    account.crm_cards.create!(pipeline: pipeline, stage: etapa, title: titulo)
  end

  def item(card)
    { card_id: card.id, suggested_stage_id: card.stage_id, confidence: 0.9, reasoning: 'ok', value: nil, handoff: nil,
      callback_request: nil, extracted_attributes: { contact: [], conversation: [], card: [] }, score_signals: nil }
  end

  it 'card que a IA não respondeu fica sem avaliação; card estranho e card repetido são ignorados' do
    allow(cliente).to receive(:create).and_return(text: { cards: [item(auto), item(auto).merge(confidence: 0.1), { card_id: 999_999 }] }.to_json)

    resultados = described_class.new(cards: [auto, residencial], principal: auto).perform

    expect(resultados[residencial.id]).to have_attributes(status: :skipped, error: 'sem_resposta')
    expect(resultados[auto.id].status).to eq(:skipped)
    expect(auto.reload.metadata.dig('ai', 'last_evaluated_at')).to be_present
    expect(residencial.reload.metadata.dig('ai', 'last_evaluated_at')).to be_nil
    expect(cliente).to have_received(:create).once
  end

  it 'falha da IA vira falha de cada card, sem levantar' do
    allow(cliente).to receive(:create).and_raise(Crm::Ai::ResponsesClient::Error, 'timeout')

    resultados = described_class.new(cards: [auto, residencial], principal: auto).perform

    expect(resultados.values.map(&:status)).to eq(%i[failed failed])
  end

  describe Crm::Ai::EvaluateCardsJob do
    it 'pula o card que ganhou um agendamento mais novo' do
      allow(Crm::Ai::AvaliacaoConjunta).to receive(:new).and_return(instance_double(Crm::Ai::AvaliacaoConjunta, perform: {}))
      token = Time.current.to_f
      Crm::Ai::Observer.new(card: auto).marcar(token)
      Crm::Ai::Observer.new(card: residencial).marcar(token + 10)

      described_class.perform_now([auto.id, residencial.id], residencial.id, token)

      expect(Crm::Ai::AvaliacaoConjunta).to have_received(:new).with(cards: [auto], principal: nil)
    end
  end
end
