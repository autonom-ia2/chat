require 'rails_helper'

# Porte de lib/services/scoring/negative-factors.test.ts do Orth (#681): penalidades que descem a prioridade. Já no CRM
# e contato recente vêm do lead (quem chama preenche); avaliação velha e nota baixa com poucas avaliações vêm do Google.
RSpec.describe Autonomia::Prospecting::Scoring::NegativeFactors do
  let(:now) { Time.utc(2026, 1, 15) }

  def call(lead = {})
    described_class.call(Autonomia::Prospecting::Scoring::LeadSignals.from(lead), reference_time: now)
  end

  def keys(result)
    result[:factors].pluck('key')
  end

  it 'lead limpo não tem penalidade' do
    result = call(rating: 4.5, reviews_count: 100)

    expect(result[:total_penalty]).to eq(0)
    expect(result[:factors]).to eq([])
  end

  describe 'já no CRM' do
    it 'tira 40 pontos' do
      result = call(already_in_crm: true)

      expect(result[:total_penalty]).to eq(40)
      expect(result[:factors]).to eq([{ 'key' => 'already_in_crm', 'points' => -40, 'reason' => 'Já está no CRM' }])
    end

    it 'cita o funil quando vem o nome' do
      expect(call(already_in_crm: true, crm_funnel_name: 'Vendas Q4')[:factors].first['reason']).to eq('Já está no funil "Vendas Q4"')
    end
  end

  describe 'contato recente' do
    it 'tira 20 pontos' do
      result = call(recently_contacted: true, days_since_last_contact: 3)

      expect(result[:total_penalty]).to eq(20)
      expect(result[:factors].first).to include('key' => 'recently_contacted', 'reason' => 'Contatado há 3d')
    end

    it 'não soma com já no CRM, que é o mesmo motivo' do
      result = call(already_in_crm: true, recently_contacted: true)

      expect(keys(result)).to eq(['already_in_crm'])
      expect(result[:total_penalty]).to eq(40)
    end
  end

  describe 'avaliação velha' do
    it 'tira 10 pontos quando a última avaliação tem mais de 2 anos' do
      result = call(reviews: [{ 'publishTime' => '2023-01-01T00:00:00Z' }, { 'publishTime' => '2022-06-01T00:00:00Z' }])
      factor = result[:factors].find { |item| item['key'] == 'old_reviews' }

      expect(factor['points']).to eq(-10)
      expect(factor['reason']).to include('3 anos')
    end

    it 'não conta avaliação com menos de 2 anos' do
      expect(keys(call(reviews: [{ 'publishTime' => '2025-06-01T00:00:00Z' }]))).not_to include('old_reviews')
    end

    it 'não conta quando nenhuma data se lê' do
      expect(keys(call(reviews: [{ 'publishTime' => 'invalid-date' }]))).not_to include('old_reviews')
    end

    it 'não conta sem avaliações' do
      expect(keys(call)).not_to include('old_reviews')
    end
  end

  describe 'nota baixa com poucas avaliações' do
    it 'tira 15 pontos com nota abaixo de 2.0 e de 1 a 4 avaliações' do
      factor = call(rating: 1.5, reviews_count: 3)[:factors].find { |item| item['key'] == 'low_rating_low_volume' }

      expect(factor['points']).to eq(-15)
      expect(factor['reason']).to eq('Rating 1.5 com apenas 3 reviews')
    end

    it 'não conta com nota 2.0 ou mais, 5 avaliações ou mais, ou zero avaliação' do
      expect(keys(call(rating: 2.5, reviews_count: 3))).not_to include('low_rating_low_volume')
      expect(keys(call(rating: 1.5, reviews_count: 5))).not_to include('low_rating_low_volume')
      expect(keys(call(rating: 1.5, reviews_count: 0))).not_to include('low_rating_low_volume')
    end
  end

  it 'soma fatores independentes' do
    result = call(rating: 1.5, reviews_count: 2, reviews: [{ 'publishTime' => '2023-01-01T00:00:00Z' }],
                  already_in_crm: true, crm_funnel_name: 'X')

    expect(result[:total_penalty]).to eq(65)
    expect(result[:factors].size).to eq(3)
  end
end
