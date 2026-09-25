require 'rails_helper'

# Porte de lib/services/scoring/priority-score.test.ts do Orth (#681): prioridade = nota × contato × decisor × aberto
# agora − penalidade, normalizada por percentil dentro da busca.
RSpec.describe Autonomia::Prospecting::Scoring::Priority do
  def input(base_score: 50, lead: {}, negative_penalty: 0, open_now_filter_active: false)
    { base_score: base_score, signals: Autonomia::Prospecting::Scoring::LeadSignals.from(lead),
      negative_penalty: negative_penalty, open_now_filter_active: open_now_filter_active }
  end

  describe '.factors' do
    it 'WhatsApp verificado e decisor achado dão multiplicador 1.56' do
      result = described_class.factors(**input(lead: { phone: '+55 11 99999-9999', whatsapp_verified: true, decisor_found: true }))

      expect(result).to include(contactability: 1.3, decisor: 1.2, hour: 1.0)
      expect(result[:raw_multiplier]).to be_within(0.005).of(1.56)
      expect(result[:raw_priority]).to be_within(0.5).of(78)
    end

    it 'sem telefone o contato vale 0.3' do
      result = described_class.factors(**input(base_score: 80))

      expect(result[:contactability]).to eq(0.3)
      expect(result[:raw_priority]).to be_within(0.5).of(24)
    end

    it 'decisor que falhou pesa 0.8 e pendente 1.0' do
      lead = { phone: '+55 11 99999-9999' }

      expect(described_class.factors(**input(lead: lead))[:decisor]).to eq(1.0)
      expect(described_class.factors(**input(lead: lead.merge(decisor_failed: true)))[:decisor]).to eq(0.8)
    end

    it 'aberto agora dá 1.15 quando o filtro de aberto agora não está ligado' do
      lead = { phone: '+55 11 99999-9999', open_now: true }

      expect(described_class.factors(**input(lead: lead, open_now_filter_active: false))[:hour]).to eq(1.15)
    end

    it 'aberto agora não dá bônus quando o filtro de aberto agora está ligado' do
      lead = { phone: '+55 11 99999-9999', open_now: true }

      expect(described_class.factors(**input(lead: lead, open_now_filter_active: true))[:hour]).to eq(1.0)
    end

    it 'a penalidade sai depois do multiplicador' do
      result = described_class.factors(**input(lead: { phone: '+55 11 99999-9999' }, negative_penalty: 30))

      expect(result[:raw_priority]).to eq(20)
    end
  end

  describe '.rank' do
    it 'lista vazia devolve vazio' do
      expect(described_class.rank([])).to eq([])
    end

    it 'lead único fica com 100 e posição 1' do
      result = described_class.rank([input(base_score: 30)])

      expect(result.size).to eq(1)
      expect(result.first).to include(priority_score: 100, priority_position: 1)
    end

    it 'o topo vira 100 e o último vira 0, na ordem de entrada' do
      result = described_class.rank([input(base_score: 90), input(base_score: 50), input(base_score: 10)])

      expect(result.map { |item| item[:priority_score] }).to eq([100, 50, 0])
      expect(result.map { |item| item[:priority_position] }).to eq([1, 2, 3])
    end

    it 'distribui o meio da faixa pelos percentis' do
      result = described_class.rank([0, 20, 40, 60, 80].map { |base| input(base_score: base) })

      expect(result.map { |item| item[:priority_score] }).to eq([0, 25, 50, 75, 100])
    end

    it 'empate de prioridade e nota divide as posições 1 e 2' do
      result = described_class.rank([input(base_score: 50), input(base_score: 50), input(base_score: 10)])

      expect(result.first(2).map { |item| item[:priority_position] }.sort).to eq([1, 2])
      expect(result.last[:priority_position]).to eq(3)
    end

    it 'com prioridade e nota iguais vence a melhor posição no Google' do
      result = described_class.rank([input(lead: { search_rank: 5 }), input(lead: { search_rank: 1 })])

      expect(result.map { |item| item[:priority_position] }).to eq([2, 1])
    end

    it 'contato muda a ordem: WhatsApp com decisor passa a nota mais alta sem telefone' do
      result = described_class.rank(
        [
          input(base_score: 80, lead: { phone: '+55 11 1' }),
          input(base_score: 60, lead: { phone: '+55 11 2', whatsapp_verified: true, decisor_found: true }),
          input(base_score: 90)
        ]
      )

      expect(result.map { |item| item[:priority_position] }).to eq([2, 1, 3])
    end
  end
end
