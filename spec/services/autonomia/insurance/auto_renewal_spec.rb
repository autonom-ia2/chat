require 'rails_helper'

# Desde a entrega 2 o bloco `quotation` chega inteiro do modelo, na forma do adapter; o que sobra
# aqui é o FATO que dispara o aviso de renovação sem bônus.
RSpec.describe Autonomia::Insurance::AutoRenewal do
  describe '#renovacao?' do
    it 'lê isRenewal do bloco quotation, com cast de string (o histórico de execuções antigas)' do
      expect(described_class.new('quotation' => { 'isRenewal' => true }).renovacao?).to be(true)
      expect(described_class.new('quotation' => { 'isRenewal' => 'true' }).renovacao?).to be(true)
      expect(described_class.new('quotation' => { 'isRenewal' => false }).renovacao?).to be(false)
      expect(described_class.new({}).renovacao?).to be(false)
    end

    it 'aceita chaves símbolo, como a Base já normaliza' do
      expect(described_class.new(quotation: { 'isRenewal' => true }).renovacao?).to be(true)
    end
  end

  describe '#sem_bonus?' do
    it 'é falso fora de renovação, onde bônus não faz sentido' do
      expect(described_class.new('quotation' => { 'isRenewal' => false }).sem_bonus?).to be(false)
    end

    it 'é verdadeiro quando o cliente renova e não soube a classe' do
      expect(described_class.new('quotation' => { 'isRenewal' => true }).sem_bonus?).to be(true)
    end

    # Quem respondeu 0 já disse o que sabia; avisar "me diga sua classe" seria ignorar a resposta.
    it 'é falso quando o cliente informou classe 0' do
      expect(described_class.new('quotation' => { 'isRenewal' => true, 'bonusClass' => 0 }).sem_bonus?).to be(false)
    end
  end
end
