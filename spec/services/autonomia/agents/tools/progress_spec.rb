require 'rails_helper'

# O CANAL DAS ENTREGAS É O DO CLIENTE, e o cabeçalho de `Progress` já dizia isso: "deliveries são
# textos DESTINADOS AO CLIENTE" e "a ferramenta NUNCA tem canal para mandar erro ao cliente".
# Faltava quem fizesse o contrato valer — em 08/09/2026 uma entrega levou `insured.document` e
# "chame a ferramenta de novo" ao WhatsApp de um cliente real.
#
# A GUARDA DEIXOU DE DESCARTAR EM 12/09/2026, E O MOTIVO É DE DINHEIRO. Uma entrega passou a ser
# "abertura + dezessete preços + aviso" numa string só; descartá-la inteira por causa de um nome de
# campo deixava o handle já avançado, as ofertas nunca mais eram reemitidas (`fresh` as exclui) e o
# cliente lia a frase de falha sobre dezessete seguradoras que a corretora pagou. Agora ela REDIGE:
# o cliente continua sem ler o nome do campo, e continua com os preços. Quem barra o texto de FORA —
# a frase que o modelo escreveu — é `TextoAoCliente.vetar`, na leitura do parâmetro, onde recuar
# custa uma frase e não a cotação.
RSpec.describe Autonomia::Agents::Tools::Progress do
  describe 'entrega com caminho de campo' do
    it 'redige o caminho de campo em vez de mandá-lo ao cliente' do
      # Arrange / Act
      progress = described_class.done(deliveries: ['Faltam: insured.document.'])

      # Assert
      expect(progress.deliveries.sole).not_to include('insured.document')
      expect(progress.deliveries.sole).to start_with('Faltam:')
    end

    it 'nao descarta a entrega, que e onde moram os precos' do
      # Perder uma frase é ruim; perder a cotação inteira é pior — e a entrega é a cotação inteira.
      progress = described_class.done(deliveries: ["Primeiros preços:\n\n• *Porto Seguro*: R$ 2.340,18 no total\n\ninsured.document"])

      expect(progress.deliveries.sole).to include('R$ 2.340,18')
      expect(progress.deliveries.sole).not_to include('insured.document')
      expect(progress.done?).to be(true)
    end

    it 'nao come as entregas boas que vieram junto' do
      progress = described_class.done(deliveries: ['**Porto Seguro** R$ 2.340,18', 'segurado.cpfCnpj'])

      expect(progress.deliveries.first).to eq('**Porto Seguro** R$ 2.340,18')
      expect(progress.deliveries.last).not_to include('cpfCnpj')
    end
  end

  # O TRAVESSÃO SAI DO QUE CHEGA AO CLIENTE (decisão do CEO, 12/09/2026). Onde ele separa colunas
  # quem compõe escolhe o substituto; aqui, no texto já composto, ele vira hífen — um nome vindo do
  # portal com travessão dentro não pode perder o sentido por causa da regra.
  it 'troca o travessao por hifen no texto que sai' do
    progress = described_class.done(deliveries: ['Comparativo — todas as opções'])

    expect(progress.deliveries.sole).to eq('Comparativo - todas as opções')
  end

  # IDEMPOTENTE: a ferramenta depura para calcular a identidade da entrega e o `Progress` depura de
  # novo. Uma segunda passada que mudasse o texto daria token gravado ≠ token publicado, e o fecho
  # perguntaria por uma mensagem que nunca existiu.
  it 'depurar duas vezes devolve o mesmo texto' do
    uma = described_class.entregavel('Comparativo — placa ABC1D23, veja insured.document  ')

    expect(described_class.entregavel(uma)).to eq(uma)
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
                                                     nome: 'Comparativo de seguro, placa ABC1D23.pdf',
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

    it 'redige o caminho de campo da legenda, e entrega o arquivo assim mesmo' do
      suja = Autonomia::Agents::Tools::EntregaDeArquivo.new(url: arquivo.url, nome: arquivo.nome,
                                                            legenda: 'Faltou insured.document', reserva: arquivo.reserva)

      entregue = Autonomia::Agents::Tools::EntregaDeArquivo.de(described_class.done(deliveries: [suja]).deliveries.sole)

      expect(entregue.legenda).not_to include('insured.document')
      expect(entregue.url).to eq(arquivo.url)
    end

    # A RESERVA é texto de cliente tanto quanto a legenda: é o que ele lê quando o arquivo falha. A
    # URL fica intacta (a reserva legítima a carrega), e o caminho de campo que sobra é redigido
    # (rodada 5, 11/09/2026 — a regra existia; faltava a guarda sobre a reserva).
    it 'redige o caminho de campo da reserva sem levar o link junto' do
      suja = Autonomia::Agents::Tools::EntregaDeArquivo.new(url: arquivo.url, nome: arquivo.nome,
                                                            legenda: arquivo.legenda,
                                                            reserva: "Faltou insured.document\n#{arquivo.url}")

      entregue = Autonomia::Agents::Tools::EntregaDeArquivo.de(described_class.done(deliveries: [suja]).deliveries.sole)

      expect(entregue.reserva).not_to include('insured.document')
      expect(entregue.reserva).to include(arquivo.url)
    end
  end
end
