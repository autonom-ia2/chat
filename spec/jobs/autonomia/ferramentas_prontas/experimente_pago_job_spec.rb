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

  it 'o pedido abre só com o id nos argumentos do job' do
    id = abrir

    expect { described_class.perform_later(id) }.to have_enqueued_job(described_class).with(id).on_queue(AgentToolsQueue::FILA)
  end
end
