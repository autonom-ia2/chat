require 'rails_helper'

# #2858 (F7, revisor 12/11): o Experimente Premium em segundo plano. Uma passada por pedido (a consulta é paga), o texto
# digitado nunca nos argumentos do job, e o defeito vira "não consegui consultar" para a tela. A consulta em si é
# dublada aqui; o caminho inteiro, com a BigDataCorp do WebMock, está no spec de request do Premium.
RSpec.describe Autonomia::FerramentasProntas::ExperimentePagoJob do
  let(:account) { create(:account) }
  let(:pedido) { Autonomia::FerramentasProntas::Experimente::Pedido }
  let(:pago) { instance_double(Autonomia::FerramentasProntas::Experimente::Pago) }

  def abrir
    pedido.abrir!(account: account, fonte: 'certidoes_empresa', valor: 'CNPJ 11.222.333/0001-81', confirmou_preco: false)
  end

  before { allow(Autonomia::FerramentasProntas::Experimente::Pago).to receive(:new).and_return(pago) }

  it 'roda a consulta uma vez e grava o resultado no lugar do pedido, sem o texto digitado' do
    allow(pago).to receive(:call).and_return('situacao' => 'encontrado', 'dados' => { 'situacao' => 'NEGATIVA' })
    id = abrir

    described_class.perform_now(id)
    described_class.perform_now(id)

    expect(pago).to have_received(:call).once
    expect(pedido.para_tela(id, account: account)).to eq('situacao' => 'encontrado', 'dados' => { 'situacao' => 'NEGATIVA' })
    expect(pedido.ler(id)).not_to include('valor')
  end

  it 'a hora em que o pedido abriu fica no servidor e não vai à tela' do
    id = abrir

    expect(pedido.ler(id)['aberto_em']).to be_a(Float)
    expect(pedido.para_tela(id, account: account)).to eq('situacao' => 'consultando')
  end

  it 'o job que o Sidekiq devolve à fila depois de começar não consulta de novo' do
    allow(pago).to receive(:call).and_return('situacao' => 'encontrado')
    id = abrir
    pedido.reivindicar(id)

    described_class.perform_now(id)

    expect(pago).not_to have_received(:call)
    expect(pedido.para_tela(id, account: account)).to eq('situacao' => 'consultando')
  end

  it 'o defeito vai ao rastreador e a tela recebe "não consegui consultar"' do
    allow(pago).to receive(:call).and_raise(NoMethodError)
    allow(ChatwootExceptionTracker).to receive(:new).and_call_original
    id = abrir

    described_class.perform_now(id)

    expect(pedido.para_tela(id, account: account)).to eq('situacao' => 'nao_consegui_consultar')
    expect(ChatwootExceptionTracker).to have_received(:new).with(instance_of(NoMethodError), account: account)
  end

  it 'o job que começa depois do que cabe no prazo da tela não consulta: a tela diz que nada foi cobrado' do
    allow(pago).to receive(:call)
    id = abrir

    travel_to((described_class::PRAZO_PARA_COMECAR + 1.second).from_now) { described_class.perform_now(id) }

    expect(pago).not_to have_received(:call)
    expect(pedido.para_tela(id, account: account)).to eq('situacao' => 'nao_comecou')
  end

  it 'o job que começa dentro do prazo consulta normalmente' do
    allow(pago).to receive(:call).and_return('situacao' => 'encontrado')
    id = abrir

    travel_to((described_class::PRAZO_PARA_COMECAR - 1.second).from_now) { described_class.perform_now(id) }

    expect(pago).to have_received(:call).once
  end

  # #2946: o prazo da tela sai do prazo para começar, das duas idas ao modelo, da consulta Premium mais lenta do catálogo
  # (os processos e as empresas na região, 120 s, mais a folga) e da gravação. Uma consulta mais lenta estica a tela.
  it 'o prazo da tela sai dos prazos: começar, as duas idas ao modelo, a consulta mais lenta do catálogo e a gravação' do
    premium = Autonomia::FerramentasProntas::Premium
    consulta_mais_lenta = (premium::Dataset::PRAZO_DAS_LENTAS + premium::ConsultaPaga::FOLGA).seconds
    modelo = Autonomia::FerramentasProntas::Experimente::ComModelo::PRAZO_DO_MODELO.seconds

    expect(premium.prazo_maximo.seconds).to eq(consulta_mais_lenta)
    expect(pedido::PRAZO_DA_TELA).to eq(
      described_class::PRAZO_PARA_COMECAR + (2 * modelo) + consulta_mais_lenta + described_class::FOLGA_DA_GRAVACAO
    )
    expect(pedido::PRAZO_DA_TELA).to eq(145.seconds)
    expect(described_class::PRAZO_PARA_COMECAR).to eq(9.seconds)
  end

  it 'o defeito vai também ao log, com conta, fonte e classe do erro, e sem o texto digitado' do
    allow(pago).to receive(:call).and_raise(NoMethodError, 'detalhe interno')
    allow(Rails.logger).to receive(:error)

    described_class.perform_now(abrir)

    expect(Rails.logger).to have_received(:error).with(
      a_string_including("account=#{account.id}", 'fonte=certidoes_empresa', 'NoMethodError')
        .and(satisfy { |linha| linha.exclude?('11.222.333') && linha.exclude?('CNPJ') })
    )
  end

  it 'o pedido abre só com o id nos argumentos do job' do
    id = abrir

    expect { described_class.perform_later(id) }.to have_enqueued_job(described_class).with(id).on_queue(AgentToolsQueue::FILA)
  end
end
