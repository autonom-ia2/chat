require 'rails_helper'

# E4 (#2897): a bateria que mede o modelo no ramo → tipo. Aqui o modelo é um dublê: a bateria de verdade é chamada paga e
# só roda à mão (lib/tasks/carteira_ramos.rake).
RSpec.describe Carteira::Trazer::AvaliacaoDosRamos, :aggregate_failures do
  let(:casos) do
    [{ 'ramo' => 'Automóvel', 'tipo' => 'auto' }, { 'ramo' => 'RC Prof.', 'tipo' => 'empresarial' }, { 'ramo' => 'VG/APC', 'tipo' => 'vida' },
     { 'ramo' => 'Pet', 'tipo' => 'outro' }]
  end
  let(:pergunta) { instance_double(Carteira::Trazer::PerguntaDoRamo, uso: { chamadas: 1, input_tokens: 2_000_000, output_tokens: 10 }) }

  before { allow(pergunta).to receive(:call).and_return('automóvel' => 'auto', 'rc prof.' => 'auto', 'vg/apc' => 'vida') }

  it 'pergunta os ramos como a leitura da planilha pergunta e conta o acerto por tipo, a confusão, os erros e o custo' do
    resultado = described_class.new(casos, pergunta: pergunta, teto: 1, modelo: 'jev-1.13.0').call

    expect(pergunta).to have_received(:call).with(['automóvel', 'rc prof.', 'vg/apc', 'pet']).once
    expect([resultado.total, resultado.acertos]).to eq([4, 2])
    expect(resultado.por_tipo).to eq('auto' => [1, 1], 'empresarial' => [0, 1], 'vida' => [1, 1], 'outro' => [0, 1])
    expect(resultado.matriz).to eq(%w[auto auto] => 1, %w[empresarial auto] => 1, %w[vida vida] => 1, %w[outro sem_resposta] => 1)
    expect(resultado.erros).to eq([['RC Prof.', 'empresarial', 'auto'], %w[Pet outro sem_resposta]])
    expect(resultado.custo).to be_within(0.0001).of(0.084)
  end

  it 'para antes de chamar o modelo quando a rodada passa do teto de chamadas' do
    muitos = (1..41).map { |numero| { 'ramo' => "Ramo #{numero}", 'tipo' => 'outro' } }
    avaliacao = described_class.new(muitos, pergunta: pergunta, teto: 1)

    expect(avaliacao.chamadas).to eq(2)
    expect { avaliacao.call }.to raise_error(described_class::TetoDeChamadas)
    expect(pergunta).not_to have_received(:call)
  end

  it 'os casos versionados são só ramos, cada um com um dos cinco tipos, e cabem no teto padrão de 4 chamadas' do
    versionados = described_class.casos

    expect(versionados.map(&:keys).uniq).to eq([%w[ramo tipo]])
    expect(versionados.pluck('tipo').uniq).to match_array(Carteira::Apolice::TIPOS)
    expect(versionados.size).to be >= 120
    expect(described_class.new(versionados, pergunta: pergunta, teto: 4).chamadas).to eq(4)
  end
end
