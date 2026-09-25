require 'rails_helper'

# Porte de lib/services/scoring/human-insight.test.ts do Orth (#681). Duas trocas no texto, de propósito: "GBP" vira
# "GMN" e o travessão que separa a categoria dos sinais vira dois-pontos (regra do Rodrigo: nada de travessão).
RSpec.describe Autonomia::Prospecting::Scoring::HumanInsight do
  def comp(key, weight, points)
    { 'key' => key, 'weight' => weight, 'points' => points }
  end

  def build(total, mode: 'gbp', components: [])
    described_class.build(total: total, mode: mode, components: components)
  end

  describe 'categorias do modo GMN' do
    it 'segue os cortes 65 e 40' do
      expect(build(70)).to start_with('Oportunidade alta')
      expect(build(65)).to start_with('Oportunidade alta')
      expect(build(50)).to start_with('Oportunidade média')
      expect(build(40)).to start_with('Oportunidade média')
      expect(build(20)).to start_with('Oportunidade baixa')
    end
  end

  describe 'categorias do modo Geral' do
    it 'segue os cortes 70 e 50' do
      expect(build(75, mode: 'general')).to start_with('Lead bem qualificado')
      expect(build(70, mode: 'general')).to start_with('Lead bem qualificado')
      expect(build(55, mode: 'general')).to start_with('Lead qualificado')
      expect(build(50, mode: 'general')).to start_with('Lead qualificado')
      expect(build(30, mode: 'general')).to start_with('Qualificação fraca')
    end
  end

  describe 'sinais' do
    it 'GMN: entram os 3 sinais de maior peso relativo' do
      result = build(70, components: [comp('website', 30, 30), comp('phone', 10, 10), comp('rating', 20, 20),
                                      comp('volume', 15, 5), comp('activity', 10, 1), comp('photos', 15, 1)])

      expect(result).to eq('Oportunidade alta: sem site, sem telefone, nota fraca.')
      expect(result).not_to include('volume saudável')
    end

    it 'GMN: a atividade fala de GMN, não de GBP' do
      result = build(70, components: [comp('activity', 10, 10), comp('photos', 15, 1)])

      expect(result).to eq('Oportunidade alta: GMN inativo, fotos ok.')
    end

    it 'Geral: os sinais fortes usam frases positivas' do
      result = build(75, mode: 'general', components: [comp('website', 30, 30), comp('phone', 10, 10), comp('rating', 20, 20)])

      expect(result).to eq('Lead bem qualificado: site, telefone, nota alta.')
    end

    it 'ignora sinal com peso zero, zerado por filtro' do
      result = build(70, components: [comp('website', 0, 0), comp('phone', 10, 10), comp('rating', 20, 20), comp('photos', 15, 15)])

      expect(result).not_to include('site')
      expect(result).to include('sem telefone')
    end

    it 'termina com ponto final' do
      expect(build(70, components: [comp('website', 30, 30)])).to end_with('.')
    end

    it 'sem sinais fica só a categoria, sem separador' do
      expect(build(70)).to eq('Oportunidade alta')
    end

    it 'nunca usa travessão' do
      expect(build(70, components: [comp('website', 30, 30), comp('phone', 10, 0)])).not_to include('—')
    end

    it 'é determinístico' do
      first = build(70, components: [comp('website', 30, 30), comp('phone', 10, 10), comp('rating', 20, 15)])
      second = build(70, components: [comp('website', 30, 30), comp('phone', 10, 10), comp('rating', 20, 15)])

      expect(first).to eq(second)
    end
  end
end
