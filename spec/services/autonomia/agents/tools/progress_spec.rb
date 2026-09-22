require 'rails_helper'

# O CANAL DAS ENTREGAS É SÓ DE ARQUIVO (PR C). Até aqui `deliveries` eram "textos DESTINADOS AO CLIENTE", e uma
# peneira redigia o que escapava (em 08/09/2026 uma entrega levou `insured.document` ao WhatsApp de um cliente
# real). Desde a decisão do CEO de 22/09/2026 o motor não publica texto nenhum: o que o cliente lê sobre a
# cotação é a Lia quem escreve, num turno acionado por evento. O texto que chegar aqui é descartado, registrado.
RSpec.describe Autonomia::Agents::Tools::Progress do
  let(:arquivo) do
    Autonomia::Agents::Tools::EntregaDeArquivo.new(url: 'https://portal.exemplo.com/v1/quotation.pdf',
                                                   nome: 'Comparativo de seguro, placa ABC1D23.pdf')
  end

  describe 'o texto nao passa' do
    it 'descarta texto, registrado, sem derrubar a execucao' do
      allow(Rails.logger).to receive(:warn)

      progress = described_class.done(deliveries: ['Faltam: insured.document.', "Preços:\n• *Porto*: R$ 2.340,18"])

      expect(progress.deliveries).to be_empty
      expect(progress.done?).to be(true)
      expect(Rails.logger).to have_received(:warn).with(/entrega descartada: texto/).twice
    end

    it 'entrega o arquivo que veio junto do texto' do
      progress = described_class.done(deliveries: ['texto que não sai', arquivo])

      expect(progress.deliveries).to eq([arquivo.to_h])
    end
  end

  describe 'entrega de arquivo' do
    it 'aceita a forma serializada, que e como ela volta do handle' do
      progress = described_class.done(deliveries: [arquivo.to_h])

      expect(Autonomia::Agents::Tools::EntregaDeArquivo.de(progress.deliveries.first)).to have_attributes(url: arquivo.url)
    end

    # A FORMA DA VERSÃO ANTERIOR tinha legenda e reserva; as duas chaves são ignoradas, e o arquivo sai sem texto.
    it 'aceita a forma antiga, com legenda e reserva, e devolve so url e nome' do
      antiga = { 'arquivo' => arquivo.to_h['arquivo'].merge('legenda' => 'Segue.', 'reserva' => 'Segue:') }

      expect(described_class.done(deliveries: [antiga]).deliveries).to eq([arquivo.to_h])
    end

    it 'descarta um Hash que nao e entrega de arquivo' do
      progress = described_class.done(deliveries: [{ 'quote_id' => 'abc:1' }, arquivo])

      expect(progress.deliveries).to eq([arquivo.to_h])
    end

    it 'entregavel e idempotente' do
      uma = described_class.entregavel(arquivo)

      expect(described_class.entregavel(uma)).to eq(uma)
    end

    it 'limita a quantidade' do
      arquivos = Array.new(7) { |i| arquivo.to_h.deep_merge('arquivo' => { 'url' => "https://x.test/#{i}.pdf" }) }

      expect(described_class.done(deliveries: arquivos).deliveries.size).to eq(described_class::MAX_DELIVERIES)
    end
  end

  # O DESFECHO QUE A CONSULTA JÁ CONHECE viaja como EVENTO, de lista fechada.
  describe '#evento' do
    it 'carrega o tipo da lista fechada' do
      expect(described_class.done(evento: 'falta_dado').evento).to eq('falta_dado')
      expect(described_class.done(evento: :ramo_desconhecido).evento).to eq('ramo_desconhecido')
    end

    it 'descarta o tipo fora da lista, e nil sem evento' do
      expect(described_class.done(evento: 'frase pronta ao cliente').evento).to be_nil
      expect(described_class.done.evento).to be_nil
    end
  end

  it 'so entregavel e publica entre os metodos de classe da entrega' do
    expect(described_class).to respond_to(:entregavel)
    expect(described_class.singleton_class.private_method_defined?(:descartar)).to be(true)
  end

  # O PEDIDO DE CONSULTA LOGO (fatia 2 do #420): só a passada `running` o carrega; por padrão, não.
  describe '#confirmar_logo?' do
    it 'vale só para running pedido pela ferramenta' do
      expect(described_class.running(confirmar_logo: true).confirmar_logo?).to be(true)
      expect(described_class.running.confirmar_logo?).to be(false)
      expect(described_class.running(confirmar_logo: 'sim').confirmar_logo?).to be(false)
      expect(described_class.new(status: :done, confirmar_logo: true).confirmar_logo?).to be(false)
      expect(described_class.failed('x').confirmar_logo?).to be(false)
    end
  end
end
