require 'rails_helper'

# #2543: o texto do privado é medido em bytes UTF-8, como a Meta mede. A régua é uma só, a do cuidado dos comentários.
RSpec.describe Crm::MetaAds::InstagramPrivateReply do
  describe '.valid_text!' do
    def code_for(text)
      described_class.valid_text!(text)
      nil
    rescue described_class::Error => e
      e.code
    end

    it 'usa a régua de Crm::MetaAdsCommentCare::MESSAGE_LIMIT, que é de 1000 bytes' do
      expect(Crm::MetaAdsCommentCare::MESSAGE_LIMIT).to eq(1000)
    end

    it 'devolve o texto sem os espaços das pontas' do
      expect(described_class.valid_text!("  Oi, Carla!\n")).to eq('Oi, Carla!')
    end

    it 'texto vazio ou só espaço: invalid_text' do
      expect(code_for(nil)).to eq('invalid_text')
      expect(code_for("  \n")).to eq('invalid_text')
    end

    it 'aceita até 1000 bytes, contando acento como 2 bytes' do
      expect(code_for('a' * 1000)).to be_nil
      expect(code_for('ã' * 500)).to be_nil
    end

    it 'texto com acento abaixo de 1000 letras e acima de 1000 bytes: text_too_long' do
      texto = 'ã' * 501

      expect(texto.length).to be < 1000
      expect(texto.bytesize).to be > 1000
      expect(code_for(texto)).to eq('text_too_long')
    end

    it 'emoji conta 4 bytes' do
      expect(code_for('🙂' * 250)).to be_nil
      expect(code_for('🙂' * 251)).to eq('text_too_long')
    end

    it 'os espaços das pontas não contam' do
      expect(code_for("  #{'a' * 1000}  ")).to be_nil
    end
  end
end
