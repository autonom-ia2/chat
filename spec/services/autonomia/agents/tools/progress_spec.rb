require 'rails_helper'

# O CANAL DAS ENTREGAS É O DO CLIENTE, e o cabeçalho de `Progress` já dizia isso: "deliveries são
# textos DESTINADOS AO CLIENTE" e "a ferramenta NUNCA tem canal para mandar erro ao cliente".
# Faltava quem fizesse o contrato valer — em 08/09/2026 uma entrega levou `insured.document` e
# "chame a ferramenta de novo" ao WhatsApp de um cliente real.
RSpec.describe Autonomia::Agents::Tools::Progress do
  describe 'entrega com caminho de campo' do
    it 'descarta em vez de mandar ao cliente' do
      # Arrange / Act
      progress = described_class.done(deliveries: ['Faltam: insured.document.'])

      # Assert
      expect(progress.deliveries).to be_empty
    end

    it 'descarta sem derrubar a execucao' do
      # Perder uma frase é ruim; perder a cotação inteira é pior.
      progress = described_class.done(deliveries: ['Faltam: insured.document.'])

      expect(progress.done?).to be(true)
    end

    it 'nao come as entregas boas que vieram junto' do
      progress = described_class.done(deliveries: ['**Porto Seguro** R$ 2.340,18', 'segurado.cpfCnpj'])

      expect(progress.deliveries).to eq(['**Porto Seguro** R$ 2.340,18'])
    end
  end

  # A ARMADILHA DA GUARDA. O comparativo é uma entrega legítima e carrega uma URL, cujo host casa
  # com o padrão de caminho de campo. Guarda que come o comparativo troca um bug de texto por um
  # entregável perdido — por isso a URL sai antes de olhar.
  it 'entrega o comparativo em PDF, que tem URL' do
    texto = "Comparativo com todas as opções:\nhttps://portal.exemplo.test/cotacao/9.pdf"

    progress = described_class.done(deliveries: [texto])

    expect(progress.deliveries).to eq([texto])
  end

  it 'entrega preco em reais, que tem ponto de milhar' do
    progress = described_class.done(deliveries: ['**Azul** R$ 2.610,00 por ano.'])

    expect(progress.deliveries).to eq(['**Azul** R$ 2.610,00 por ano.'])
  end

  it 'entrega frase comum, que tem ponto seguido de espaco' do
    texto = 'Cotação em andamento. Assim que chegarem os preços eu mando aqui.'

    progress = described_class.done(deliveries: [texto])

    expect(progress.deliveries).to eq([texto])
  end

  # A ENTREGA DE ARQUIVO (entrega 11): o comparativo em PDF viaja como forma serializada, ao lado
  # dos textos. Ela passa pela mesma peneira — a legenda e a reserva são texto de cliente — e o que
  # não tem a forma de uma entrega de arquivo não passa: um Hash qualquer não é texto nem arquivo.
  describe 'entrega de arquivo' do
    let(:arquivo) do
      Autonomia::Agents::Tools::EntregaDeArquivo.new(url: 'https://portal.exemplo.test/cotacao/9.pdf',
                                                     nome: 'Comparativo de seguro — placa ABC1D23.pdf',
                                                     legenda: 'Comparativo com todas as opções.',
                                                     reserva: "Comparativo com todas as opções:\nhttps://portal.exemplo.test/cotacao/9.pdf")
    end

    it 'entrega o arquivo, na forma serializada, ao lado dos textos' do
      progress = described_class.done(deliveries: ['**Ezze** R$ 2.050,40', arquivo])

      expect(progress.deliveries).to eq(['**Ezze** R$ 2.050,40', arquivo.to_h])
    end

    it 'aceita a forma serializada, que e como ela volta do handle' do
      progress = described_class.done(deliveries: [arquivo.to_h])

      expect(Autonomia::Agents::Tools::EntregaDeArquivo.de(progress.deliveries.first)).to have_attributes(url: arquivo.url)
    end

    it 'descarta um Hash que nao e entrega de arquivo, sem derrubar a execucao' do
      progress = described_class.done(deliveries: [{ 'quote_id' => 'abc:1' }, 'texto bom'])

      expect(progress.deliveries).to eq(['texto bom'])
      expect(progress.done?).to be(true)
    end

    it 'descarta o arquivo cuja legenda levaria caminho de campo ao cliente' do
      suja = Autonomia::Agents::Tools::EntregaDeArquivo.new(url: arquivo.url, nome: arquivo.nome,
                                                            legenda: 'Faltou insured.document', reserva: arquivo.reserva)

      expect(described_class.done(deliveries: [suja]).deliveries).to be_empty
    end
  end
end
