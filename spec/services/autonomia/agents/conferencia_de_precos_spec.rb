require 'rails_helper'

# A CONFERÊNCIA DA FALA DA LIA COM PREÇO (fatia 3 do #420). O modelo da reescrita é o bloco: aqui ele é um
# lambda que devolve o Hash que o `Answerer` devolveria.
RSpec.describe Autonomia::Agents::ConferenciaDePrecos do
  let(:texto) do
    "2 seguradoras fizeram proposta nesta cotação.\n" \
      "Porto Seguro fez proposta: R$ 2.119,18 no total, ou 10x de R$ 211,92.\n" \
      "Bp Assinatura fez proposta: R$ 298,43 por mês.\n" \
      'Sancor não fez proposta nesta cotação.'
  end
  let(:dados) do
    described_class::Dados.new(texto: texto, seguradoras: ['Porto Seguro', 'Bp Assinatura', 'Sancor', 'Allianz'],
                               comparativo: true)
  end
  let(:conferencia) { described_class.new(dados, conversa: 7) }

  describe '.valores' do
    it 'lê valor com e sem cifrão, com milhar, sem centavos e o da parcela, em centavos' do
      valores = described_class.valores('R$ 2.119,18, ou 10x de R$ 211,92; 1.321,25 e R$ 1.500. Fim R$ 80')

      expect(valores).to contain_exactly(211_918, 21_192, 132_125, 150_000, 8_000)
    end

    it 'não lê contagem, parcela sem valor, percentual nem data como valor' do
      expect(described_class.valores('as 3 mais baratas, em 10x, com 3,5% de desconto, dia 12/09')).to be_empty
    end
  end

  describe '#publicavel' do
    it 'a fala com valor e nome dos dados sai como veio, sem pedir reescrita' do
      fala = 'A mais barata no total é a *Porto Seguro*: *R$ 2.119,18* no total, ou 10x de R$ 211,92.'

      expect(conferencia.publicavel(fala) { raise 'não devia reescrever' }).to eq(fala)
    end

    it 'valor inventado pede UMA reescrita, e a reescrita conferida sai' do
      pedidos = []
      certa = 'A *Porto Seguro* ficou em *R$ 2.119,18* no total.'

      saida = conferencia.publicavel('A Porto Seguro ficou em R$ 1.999,00 no total.') do |pedido|
        pedidos << pedido
        { 'reply' => certa, 'reply_sem_valores' => 'Os valores estão no comparativo.' }
      end

      expect(saida).to eq(certa)
      expect(pedidos.size).to eq(1)
      expect(pedidos.first).to include(texto)
    end

    it 'valor arredondado também diverge' do
      saida = conferencia.publicavel('A Porto Seguro ficou em R$ 2.119 no total.') do
        { 'reply' => 'A Porto Seguro ficou em R$ 2.119 no total.', 'reply_sem_valores' => 'Está no comparativo.' }
      end

      expect(saida).to eq('Está no comparativo.')
    end

    it 'seguradora da cotação que não está nos dados do turno diverge' do
      saida = conferencia.publicavel('A Allianz também fez proposta.') do
        { 'reply' => 'A Allianz fez.', 'reply_sem_valores' => 'Os valores estão no comparativo.' }
      end

      expect(saida).to eq('Os valores estão no comparativo.')
    end

    it 'reescrita que ainda diverge sai sem valores, e a versão sem valores com valor não passa' do
      saida = conferencia.publicavel('Porto Seguro: R$ 1,00.') do
        { 'reply' => 'Porto Seguro: R$ 2,00.', 'reply_sem_valores' => 'Porto Seguro: R$ 2.119,18.' }
      end

      expect(saida).to eq(described_class::RECUO_COM_COMPARATIVO)
    end

    it 'a chamada da reescrita que falha dá o recuo, registrado no log' do
      allow(Rails.logger).to receive(:warn)

      saida = conferencia.publicavel('Porto Seguro: R$ 1,00.') { raise Crm::Ai::ResponsesClient::Error, 'timeout' }

      expect(saida).to eq(described_class::RECUO_COM_COMPARATIVO)
      expect(Rails.logger).to have_received(:warn).with(/\[autonomia\]\[recuo\] conversa=7 papel=precos_com_comparativo/)
    end

    it 'sem comparativo entregue, o recuo não fala de comparativo' do
      sem_pdf = described_class.new(described_class::Dados.new(texto: texto, seguradoras: [], comparativo: false))

      saida = sem_pdf.publicavel('R$ 1,00') { nil }

      expect(saida).to eq(described_class::RECUO_SEM_COMPARATIVO)
      expect(saida).not_to include('comparativo')
    end

    it 'os recuos não levam valor, nome de seguradora nem travessão' do
      [described_class::RECUO_COM_COMPARATIVO, described_class::RECUO_SEM_COMPARATIVO].each do |recuo|
        expect(Autonomia::Agents::Tools::TextoAoCliente.vetar(recuo)).to eq(recuo)
      end
    end
  end

  # O VALOR É DAQUELA SEGURADORA (revisão da PR #454): valor e nome existirem nos dados não basta. As três falas
  # erradas abaixo saíam ao cliente sem reescrita.
  describe 'o valor na seguradora e no período certos' do
    let(:dados_da_cotacao) do
      described_class::Dados.new(
        texto: "4 seguradoras fizeram proposta nesta cotação.\n" \
               "Tokio Marine fez proposta: R$ 1.999,90 no total.\n" \
               "Porto Seguro fez proposta: R$ 2.119,18 no total.\n" \
               "Allianz fez proposta: R$ 2.402,55 no total.\n" \
               "Bp Assinatura fez proposta: R$ 298,43 por mês.\n" \
               'Sancor não fez proposta nesta cotação.',
        seguradoras: ['Tokio Marine', 'Porto Seguro', 'Allianz', 'Bp Assinatura', 'Sancor'], comparativo: true
      )
    end
    let(:reescrita) { { 'reply' => 'reescrita', 'reply_sem_valores' => 'Os valores estão no comparativo.' } }

    def publicado(fala)
      pedidos = []
      saida = described_class.new(dados_da_cotacao).publicavel(fala) do |pedido|
        pedidos << pedido
        reescrita
      end
      [saida, pedidos.size]
    end

    it 'os valores trocados entre duas seguradoras voltam para reescrita' do
      expect(publicado('Tokio Marine R$ 2.119,18 no total; Porto Seguro R$ 1.999,90 no total')).to eq(['reescrita', 1])
    end

    it 'a mensal dita como total volta para reescrita' do
      expect(publicado('A mais barata é a Bp Assinatura, R$ 298,43 no total.')).to eq(['reescrita', 1])
    end

    it 'o valor de outra seguradora posto na que nao fez proposta volta para reescrita' do
      expect(publicado('A Sancor ficou em R$ 2.119,18 no total.')).to eq(['reescrita', 1])
    end

    it 'as tres mais baratas com valores e periodos certos saem sem reescrita' do
      fala = 'As três mais baratas no total: *Tokio Marine* R$ 1.999,90 no total; *Porto Seguro* R$ 2.119,18 no total; ' \
             "*Allianz* R$ 2.402,55 no total.\nTem também a *Bp Assinatura*, R$ 298,43 por mês."

      expect(publicado(fala)).to eq([fala, 0])
    end
  end

  describe 'Dados#+' do
    it 'duas chamadas no turno somam texto, seguradoras e comparativo' do
      outra = described_class::Dados.new(texto: 'Allianz fez proposta: R$ 2.402,55 no total.', seguradoras: ['Allianz'],
                                         comparativo: false)

      soma = described_class::Dados.new(texto: texto, seguradoras: ['Porto Seguro'], comparativo: false) + outra

      expect(described_class.valores(soma.texto)).to include(211_918, 240_255)
      expect(soma.seguradoras).to eq(['Porto Seguro', 'Allianz'])
    end
  end
end
