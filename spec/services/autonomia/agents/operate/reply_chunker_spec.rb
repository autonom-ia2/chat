require 'rails_helper'

RSpec.describe Autonomia::Agents::Operate::ReplyChunker do
  # Defeito real de produção: o agente pediu 6 documentos para cotação de seguro e o quebrador
  # partiu a lista entre o 4º e o 5º item — o cliente recebeu a lista picotada em 4 mensagens.
  describe 'listas nunca são fragmentadas' do
    let(:items) do
      [
        '• CNH ou RG e CPF do condutor principal do veículo',
        '• Comprovante de residência recente em nome do titular',
        '• Documento do veículo (CRLV) do ano vigente',
        '• Placa e chassi, caso o CRLV ainda não tenha saído',
        '• Apólice atual, se você já tem seguro com outra seguradora',
        '• Cadastro dos demais condutores que usam o carro'
      ]
    end

    def chunks_for(text)
      described_class.call(text)
    end

    def chunks_touching_list(chunks)
      chunks.select { |chunk| items.any? { |item| chunk['text'].include?(item) } }
    end

    it 'entrega preâmbulo + lista de 6 itens + fecho com a lista INTEIRA num único pedaço' do
      # Arrange
      text = "Para seguir com a cotação, preciso destes documentos:\n\n" \
             "#{items.join("\n")}\n\n" \
             'Assim que me enviar, já preparo a cotação com as coberturas que conversamos.'

      # Act
      chunks = chunks_for(text)
      holders = chunks_touching_list(chunks)

      # Assert
      expect(holders.size).to eq(1)
      expect(items).to all(satisfy { |item| holders.first['text'].include?(item) })
    end

    it 'mantém a lista inteira mesmo quando preâmbulo e fecho estão no MESMO bloco (sem linha em branco)' do
      # Arrange
      text = "Para seguir com a cotação, preciso destes documentos:\n" \
             "#{items.join("\n")}\n" \
             'Assim que me enviar, já preparo a cotação.'

      # Act
      holders = chunks_touching_list(chunks_for(text))

      # Assert
      expect(holders.size).to eq(1)
      expect(items).to all(satisfy { |item| holders.first['text'].include?(item) })
    end

    it 'trata numeração (1. 2. 3.) e hífens como lista atômica' do
      # Arrange
      numbered = (1..6).map { |i| "#{i}. Passo número #{i} do processo de contratação da apólice nova" }
      text = "O processo tem seis etapas:\n\n#{numbered.join("\n")}\n\nQualquer dúvida é só falar."

      # Act
      chunks = chunks_for(text)
      holders = chunks.select { |chunk| numbered.any? { |item| chunk['text'].include?(item) } }

      # Assert
      expect(holders.size).to eq(1)
      expect(numbered).to all(satisfy { |item| holders.first['text'].include?(item) })
    end

    it 'continua quebrando PROSA longa fora da lista' do
      # Arrange: só prosa, bem acima do soft_max -> mais de um pedaço (comportamento preservado)
      prose = Array.new(8) { |i| "Esta é a frase número #{i} explicando um detalhe da cobertura contratada." }.join(' ')

      # Act
      chunks = chunks_for(prose)

      # Assert
      expect(chunks.size).to be > 1
    end
  end
end
