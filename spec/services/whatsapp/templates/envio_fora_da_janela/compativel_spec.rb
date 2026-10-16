require 'rails_helper'

# O "compatível" (#1587): o Jev decide, e a resposta fica no cache só enquanto a pergunta é a mesma.
RSpec.describe Whatsapp::Templates::EnvioForaDaJanela::Compativel do
  let(:account) { create(:account) }
  let(:inbox) { instance_double(Inbox, id: 7, account: account) }
  let(:jev) { instance_double(TypesafeAi::Decisor) }
  let(:tipo) { Whatsapp::Templates::EnvioForaDaJanela::Tipos.buscar('andamento') }
  let(:candidato) do
    Whatsapp::Templates::EnvioForaDaJanela::Candidatos::Candidato.new(
      nome: 'acompanhamento', idioma: 'pt_BR', categoria: 'UTILITY', texto: 'Oi, {{1}}! Seu pedido {{2}} segue.',
      campos: { '1' => 'cliente.primeiro_nome', '2' => 'negocio.titulo' }, sistema: false
    )
  end

  before do
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    allow(TypesafeAi::Config).to receive(:configured?).and_return(true)
    allow(TypesafeAi::Decisor).to receive(:new).and_return(jev)
    allow(jev).to receive(:decidir).and_return(TypesafeAi::Decisor::Resultado.new(resposta: 'acompanhamento', certeza: 0.9, modelo: 'jev'))
  end

  def escolher(com_tipo = tipo, candidatos = [candidato])
    described_class.new(inbox: inbox, tipo: com_tipo, candidatos: candidatos).call
  end

  it 'mostra ao Jev o texto com o rótulo de cada campo e devolve o candidato escolhido' do
    descricoes = []
    allow(jev).to receive(:decidir) do |decisor:, **|
      descricoes.concat(decisor.respostas.pluck('descricao'))
      TypesafeAi::Decisor::Resultado.new(resposta: 'acompanhamento', certeza: 0.9, modelo: 'jev')
    end

    expect(escolher).to eq(candidato)
    expect(descricoes.first).to include('[', 'Seu pedido')
    expect(descricoes.first).not_to include('{{')
  end

  it 'mesma pergunta: uma chamada só; propósito, candidatos ou campos diferentes perguntam de novo' do
    escolher
    escolher
    expect(jev).to have_received(:decidir).once

    escolher(tipo.with(proposito: 'Outro propósito.'))
    expect(jev).to have_received(:decidir).twice

    escolher(tipo, [candidato.with(texto: 'Oi, {{1}}! O pedido {{2}} mudou.')])
    expect(jev).to have_received(:decidir).exactly(3).times
  end

  it '"nenhum" fica no cache e devolve nil' do
    allow(jev).to receive(:decidir).and_return(TypesafeAi::Decisor::Resultado.new(resposta: 'nenhum', certeza: 0.9, modelo: 'jev'))

    2.times { expect(escolher).to be_nil }
    expect(jev).to have_received(:decidir).once
  end

  it 'sem candidatos não pergunta' do
    expect(escolher(tipo, [])).to be_nil
    expect(jev).not_to have_received(:decidir)
  end
end
