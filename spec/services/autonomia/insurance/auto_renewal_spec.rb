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

    # Fora da faixa o adapter RECUSA a cotação inteira antes de falar com o portal, e o cliente
    # espera o deadline para receber "não consegui". 30 é o erro mais provável: percentual no lugar
    # da classe. Vira nil, e não 10 — limitar inventaria um bônus que ele não tem.
    it 'descarta bônus fora da faixa em vez de derrubar a cotação ou inventar um valor' do
      [30, 11, -1].each do |fora|
        entrada = described_class.new('renovacao' => true, 'bonus' => fora).to_input

        expect(entrada['quotation']).to eq('isRenewal' => true), fora.to_s
      end
    end

    # A MESMA classe de defeito do bônus, no campo irmão. `-1` é o sentinel que um modelo inventa
    # quando a descrição avisa que 0 significa "nenhum sinistro" e não sobra jeito de dizer "não
    # sei". O adapter declara `min(0)` e recusa a cotação inteira.
    it 'descarta sinistros fora da faixa, em vez de derrubar a cotação' do
      [-1, 100].each do |fora|
        entrada = described_class.new('renovacao' => true, 'sinistros' => fora).to_input

        expect(entrada['quotation']).to eq('isRenewal' => true), fora.inspect
      end
    end

    # A classe tem spec próprio e é desenhada como unidade autônoma. Sem normalizar, chaves símbolo
    # viram "não é renovação" em silêncio — a falha mais cara possível aqui, e sem erro nenhum.
    it 'aceita chaves símbolo, como a Base já normaliza' do
      entrada = described_class.new(renovacao: true, bonus: 7).to_input

      expect(entrada['quotation']).to eq('isRenewal' => true, 'bonusClass' => 7)
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
