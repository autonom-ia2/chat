require 'rails_helper'

# A revisão de conversas em lote do Guia (#3158, B8b): o estado, "ler as que faltam" e os motivos agrupados.
RSpec.describe Autonomia::Guide::Revisao do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  def revisao(**atributos)
    described_class.create!({ account: account, user: user, status: 'concluida', titulo: 'Revisão das notas 1 e 2',
                              pedido: 'Por que a nota foi baixa', selecao: { 'de' => '2026-11-17', 'ate' => '2026-11-23' },
                              ids: (1..10).to_a, limite: 300 }.merge(atributos))
  end

  def resultado(categoria, numero) = { 'categoria' => categoria, 'motivo' => "motivo #{numero}", 'numero' => numero }

  it 'agrupa os motivos do mais comum ao menos, com as conversas de cada um', :aggregate_failures do
    lidos = [resultado('Demora', 1), resultado('Cobrança errada', 2), resultado('Demora', 3)]
    categorias = revisao(resultados: lidos, lidas: 3, posicao: 3).para_tela['categorias']

    expect(categorias.pluck('nome')).to eq(['Demora', 'Cobrança errada'])
    expect(categorias.first['conversas']).to eq([{ 'numero' => 1, 'motivo' => 'motivo 1' }, { 'numero' => 3, 'motivo' => 'motivo 3' }])
  end

  it 'junta o que passa de 5 categorias em outros' do
    lidos = %w[A A B B C C D D E E F G].each_with_index.map { |nome, indice| resultado(nome, indice) }
    categorias = revisao(resultados: lidos).categorias

    expect(categorias.size).to eq(6)
    expect(categorias.last).to include('outros' => true, 'nome' => nil)
    expect(categorias.last['conversas'].size).to eq(2)
  end

  it 'não manda os motivos enquanto lê, só a contagem' do
    expect(revisao(status: 'rodando', resultados: [resultado('Demora', 1)]).para_tela['categorias']).to eq([])
  end

  it 'repete as categorias já dadas, da mais comum' do
    lidos = [resultado('B', 1), resultado('A', 2), resultado('A', 3)]

    expect(revisao(resultados: lidos).categorias_conhecidas).to eq(%w[A B])
  end

  describe 'ler as que faltam' do
    it 'soma mais 300 a partir de onde parou e volta para a fila', :aggregate_failures do
      escolhida = revisao(ids: (1..400).to_a, posicao: 300, lidas: 300)

      expect(escolhida.continuar!).to be(true)
      expect(escolhida).to have_attributes(status: 'na_fila', limite: 600, ate: 400)
    end

    it 'recusa quando já leu tudo, ou enquanto ainda lê', :aggregate_failures do
      expect(revisao(posicao: 10).continuar!).to be(false)
      expect(revisao(status: 'rodando', ids: (1..400).to_a, posicao: 100).continuar!).to be(false)
    end

    it 'recusa enquanto a pessoa tem outra revisão andando' do
      parada = revisao(status: 'parada', ids: (1..400).to_a, posicao: 100)
      revisao(status: 'rodando')

      expect(parada.continuar!).to be(false)
    end
  end

  it 'deixa só uma revisão andando por pessoa' do
    revisao(status: 'na_fila')

    expect { revisao(status: 'rodando') }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  describe 'avançar uma conversa' do
    it 'soma a lida, o resultado e o custo no banco', :aggregate_failures do
      andando = revisao(status: 'rodando', custo: 0.5)

      expect(andando.avancar!(resultado('Demora', 1), custo: 0.25)).to be(true)
      expect(andando.avancar!(nil, custo: 0)).to be(true)
      expect(andando).to have_attributes(posicao: 2, lidas: 1, falhas: 1, resultados: [resultado('Demora', 1)])
      expect(andando.custo.to_f).to eq(0.75)
    end

    it 'não grava depois de parada nem de uma posição que outra cadeia já passou', :aggregate_failures do
      andando = revisao(status: 'rodando')
      velha = described_class.find(andando.id)
      andando.avancar!(resultado('Demora', 1), custo: 0)

      expect(velha.avancar!(resultado('Demora', 1), custo: 0)).to be(false)
      andando.parar!
      expect(andando.avancar!(nil, custo: 0)).to be(false)
      expect(andando.reload).to have_attributes(posicao: 1, lidas: 1, falhas: 0)
    end

    it 'guarda o gasto da chamada paga mesmo quando não grava a conversa' do
      parada = revisao(status: 'parada', custo: 0.1)

      expect(parada.avancar!(resultado('Demora', 1), custo: 0.05)).to be(false)
      expect(parada.reload.custo.to_f).to eq(0.15)
    end
  end

  it 'para só o que ainda anda', :aggregate_failures do
    andando = revisao(status: 'rodando')
    expect(andando.parar!).to be(true)
    expect(andando.status).to eq('parada')
    expect(revisao(status: 'concluida').parar!).to be(false)
  end
end
