require 'rails_helper'

# IA entende a conversa F3, regra i (silêncio não vira Perdido): com a flag `crm_ia_fecha_card`, a avaliação do card
# parado sai com o gatilho `card_parado`, que nunca fecha card (Crm::Ai::FecharCard). Sem a flag, o job de sempre.
RSpec.describe Crm::Ai::StaleCardsJob do
  around do |example|
    with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true') { example.run }
  end

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let!(:card) do
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Parado', currency: 'BRL').tap do |parado|
      parado.update_columns(last_activity_at: 30.days.ago) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  before do
    allow(Crm::Cards::CurrentSubject).to receive(:card?).and_return(true)
    allow(Crm::Ai::EvaluateCardJob).to receive(:perform_later)
  end

  it 'com a flag: avalia com o gatilho do card parado' do
    account.enable_features!(Crm::Ai::FecharCard::FLAG)

    described_class.perform_now

    expect(Crm::Ai::EvaluateCardJob).to have_received(:perform_later).with(card.id, nil, Crm::Ai::FecharCard::TRIGGER_CARD_PARADO)
  end

  it 'sem a flag: o job de sempre' do
    described_class.perform_now

    expect(Crm::Ai::EvaluateCardJob).to have_received(:perform_later).with(card.id)
  end
end
