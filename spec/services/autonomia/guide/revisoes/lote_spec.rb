require 'rails_helper'

# Um lote da revisão (#3158, B8b): lê conversa por conversa, guarda o motivo, para quando a pessoa para.
RSpec.describe Autonomia::Guide::Revisoes::Lote do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:revisor) { instance_double(Autonomia::Guide::Revisoes::Revisor, custo: 0.002) }
  let(:conversas) do
    Array.new(3) do
      create(:conversation, account: account).tap do |conversa|
        create(:message, conversation: conversa, account: account, inbox: conversa.inbox, message_type: :incoming, content: 'Demorou')
      end
    end
  end
  let(:revisao) do
    Autonomia::Guide::Revisao.create!(account: account, user: user, status: 'rodando', titulo: 'Revisão', pedido: 'Por quê',
                                      selecao: {}, ids: conversas.map(&:id), limite: 300)
  end

  before do
    allow(Autonomia::Guide::Revisoes::Semaforo).to receive(:entrar).and_return(true)
    allow(Autonomia::Guide::Revisoes::Revisor).to receive(:new).and_return(revisor)
    allow(revisor).to receive(:revisar).and_return({ 'categoria' => 'Demora na resposta', 'motivo' => 'Esperou 2 dias' })
  end

  it 'lê todas, guarda o motivo de cada uma e conclui', :aggregate_failures do
    expect(described_class.new(revisao).rodar).to eq(described_class::FIM)

    revisao.reload
    expect(revisao).to have_attributes(status: 'concluida', lidas: 3, falhas: 0, posicao: 3)
    expect(revisao.resultados.pluck('numero')).to eq(conversas.map(&:display_id))
    expect(revisao.custo.to_f).to eq(0.002)
  end

  it 'para quando a pessoa parou, sem somar a conversa que terminou depois', :aggregate_failures do
    allow(revisor).to receive(:revisar) do
      Autonomia::Guide::Revisao.find(revisao.id).parar!
      { 'categoria' => 'Demora', 'motivo' => 'x' }
    end

    expect(described_class.new(revisao).rodar).to eq(described_class::FIM)
    expect(revisor).to have_received(:revisar).once
    expect(revisao.reload).to have_attributes(status: 'parada', lidas: 0, posicao: 0)
  end

  it 'não grava de novo a conversa que outra cadeia do job já gravou', :aggregate_failures do
    outra = Autonomia::Guide::Revisao.find(revisao.id)
    allow(revisor).to receive(:revisar) do
      outra.avancar!({ 'categoria' => 'Demora', 'motivo' => 'da outra' }, custo: 0) if outra.posicao.zero?
      { 'categoria' => 'Demora', 'motivo' => 'desta' }
    end

    expect(described_class.new(revisao).rodar).to eq(described_class::FIM)
    expect(revisao.reload).to have_attributes(status: 'rodando', posicao: 1, lidas: 1)
    expect(revisao.resultados.pluck('motivo')).to eq(['da outra'])
  end

  it 'não lê a conversa que a dona da revisão não vê mais', :aggregate_failures do
    revisao.update!(user: create(:user, account: account, role: :agent))

    described_class.new(revisao).rodar
    expect(revisor).not_to have_received(:revisar)
    expect(revisao.reload).to have_attributes(status: 'concluida', lidas: 0, falhas: 3, resultados: [])
  end

  it 'devolve a vez ao job quando perde a vaga' do
    allow(Autonomia::Guide::Revisoes::Semaforo).to receive(:entrar).and_return(false)

    expect(described_class.new(revisao).rodar).to eq(described_class::CONTINUAR)
    expect(revisao.reload.posicao).to eq(0)
  end

  it 'conta como falha a conversa que não abre e segue', :aggregate_failures do
    conversas.first.messages.destroy_all
    allow(revisor).to receive(:revisar).and_raise(Autonomia::Guide::Revisoes::Revisor::Falhou, 'JSON::ParserError')
    allow(revisor).to receive(:revisar).with(conversas.last).and_return({ 'categoria' => 'Demora', 'motivo' => 'x' })

    described_class.new(revisao).rodar
    expect(revisao.reload).to have_attributes(status: 'concluida', lidas: 1, falhas: 2)
  end

  it 'para a revisão inteira sem chave de IA' do
    allow(revisor).to receive(:revisar).and_raise(Autonomia::Guide::Revisoes::Revisor::SemChave)

    described_class.new(revisao).rodar
    expect(revisao.reload).to have_attributes(status: 'falhou', motivo: 'sem_chave')
  end

  it 'lê só até o limite desta vez', :aggregate_failures do
    revisao.update!(limite: 2)

    described_class.new(revisao).rodar
    expect(revisao.reload).to have_attributes(status: 'concluida', posicao: 2)
    expect(revisao.para_tela['faltam']).to eq(1)
  end
end
