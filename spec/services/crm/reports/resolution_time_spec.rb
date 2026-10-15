require 'rails_helper'

# Os cenários montam datas no passado (entrada na etapa, fechamento) sem passar pelos callbacks que as regravam.
# rubocop:disable Rails/SkipsModelValidations

# Tempo de solução (#1498): do card aberto até Resolvido, sem o tempo em "Esperando o cliente".
RSpec.describe Crm::Reports::ResolutionTime do
  let!(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }

  it 'tira da conta o tempo na etapa de espera' do
    pipeline, novo = create_crm_pipeline(account: account, user: user, name: 'Suporte')
    pipeline.update!(counts_as_sale: false)
    espera = create_crm_stage(account: account, pipeline: pipeline, name: 'Esperando o cliente', position: 2)
    espera.update!(metadata: { 'category' => 'espera' })
    inicio = Time.zone.parse('2026-10-01 10:00')
    card = account.crm_cards.create!(pipeline: pipeline, stage: novo, title: 'Troca')
    card.update_columns(created_at: inicio, closed_at: inicio + 10.hours, status: Crm::Card.statuses[:resolved])
    [[inicio + 2.hours, novo, espera], [inicio + 8.hours, espera, novo]].each do |at, de, para|
      Crm::Activity.create!(account: account, card: card, actor_type: 'user', actor_id: user.id, event_type: 'move',
                            payload: { 'from_stage_id' => de.id, 'to_stage_id' => para.id }).update_columns(created_at: at)
    end

    result = described_class.new(pipeline: pipeline, cards: pipeline.cards).perform

    expect(result).to eq(count: 1, average_seconds: 4.hours.to_i, median_seconds: 4.hours.to_i)
  end

  it 'sem etapa de espera conta o tempo inteiro, e sem cards devolve vazio' do
    pipeline, novo = create_crm_pipeline(account: account, user: user, name: 'Suporte')
    expect(described_class.new(pipeline: pipeline, cards: pipeline.cards).perform[:count]).to eq(0)

    card = account.crm_cards.create!(pipeline: pipeline, stage: novo, title: 'Troca')
    card.update_columns(created_at: 3.hours.ago, closed_at: Time.current)

    expect(described_class.new(pipeline: pipeline, cards: pipeline.cards).perform[:average_seconds]).to be_within(2).of(3.hours.to_i)
  end
end
# rubocop:enable Rails/SkipsModelValidations
