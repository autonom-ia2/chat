require 'rails_helper'

RSpec.describe Autonomia::Insurance::AutoRenewal do
  describe '#to_input' do
    it 'não monta bloco nenhum quando é cotação nova' do
      expect(described_class.new('renovacao' => false).to_input).to eq({})
    end

    it 'leva bônus e sinistros quando o cliente está renovando' do
      renovacao = described_class.new('renovacao' => true, 'bonus' => 7, 'sinistros' => 1)

      expect(renovacao.to_input)
        .to eq('quotation' => { 'isRenewal' => true, 'bonusClass' => 7, 'previousClaimsCount' => 1 })
    end

    # O cast do Rails trata "não" como TRUE. Numa ferramenta em português essa é a string errada
    # mais provável, e ela cotaria como renovação um cliente que disse que não é.
    it 'entende as negativas em português, que o cast do Rails sozinho não entende' do
      ['não', 'nao', 'NÃO', ' no ', 'nenhum'].each do |negativa|
        expect(described_class.new('renovacao' => negativa).to_input).to eq({}), negativa
      end
    end

    it 'ainda entende as negativas que o cast já resolvia' do
      %w[false 0 off].each do |negativa|
        expect(described_class.new('renovacao' => negativa).to_input).to eq({}), negativa
      end
    end

    # Fora da faixa o adapter RECUSA a cotação inteira antes de falar com o portal, e o cliente
    # espera o deadline para receber "não consegui". 30 é o erro mais provável: percentual no lugar
    # da classe. Vira nil, e não 10 — limitar inventaria um bônus que ele não tem.
    it 'descarta bônus fora da faixa em vez de derrubar a cotação ou inventar um valor' do
      [30, 11, -1, 100].each do |fora|
        entrada = described_class.new('renovacao' => true, 'bonus' => fora).to_input

        expect(entrada['quotation']).to eq('isRenewal' => true), fora.to_s
      end
    end

    # Quem teve sinistro volta para a classe 0. Zero é resposta, não ausência.
    it 'preserva a classe 0, que é resposta de quem teve sinistro' do
      entrada = described_class.new('renovacao' => true, 'bonus' => 0).to_input

      expect(entrada['quotation']['bonusClass']).to eq(0)
    end

    it 'trata string vazia como ausência, porque é o modelo dizendo que não sabe' do
      entrada = described_class.new('renovacao' => true, 'bonus' => '', 'sinistros' => '').to_input

      expect(entrada['quotation']).to eq('isRenewal' => true)
    end

    it 'preserva zero sinistros, que é a resposta mais comum de quem renova' do
      entrada = described_class.new('renovacao' => true, 'sinistros' => 0).to_input

      expect(entrada['quotation']['previousClaimsCount']).to eq(0)
    end
  end

  describe '#sem_bonus?' do
    it 'é falso fora de renovação, onde bônus não faz sentido' do
      expect(described_class.new('renovacao' => false).sem_bonus?).to be(false)
    end

    it 'é verdadeiro quando o cliente renova e não soube a classe' do
      expect(described_class.new('renovacao' => true).sem_bonus?).to be(true)
    end

    it 'é verdadeiro quando o modelo mandou classe inválida' do
      expect(described_class.new('renovacao' => true, 'bonus' => 30).sem_bonus?).to be(true)
    end

    # Quem respondeu 0 já disse o que sabia; avisar "me diga sua classe" seria ignorar a resposta.
    it 'é falso quando o cliente informou classe 0' do
      expect(described_class.new('renovacao' => true, 'bonus' => 0).sem_bonus?).to be(false)
    end
  end
end
