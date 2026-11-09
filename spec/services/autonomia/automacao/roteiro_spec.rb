require 'rails_helper'

RSpec.describe Autonomia::Automacao::Roteiro do
  let(:receita) do
    { 'passos' => [{ 'id' => 's1', 'tipo' => 'se', 'entao' => [{ 'id' => 'a1' }, { 'id' => 'a2' }], 'senao' => [] },
                   { 'id' => 'e1', 'tipo' => 'esperar_ate', 'se_vencer' => [{ 'id' => 'v1' }] }] }
  end
  let(:roteiro) { described_class.new(receita) }

  it 'anda pelos ramos e sai deles no passo depois de quem os abriu', :aggregate_failures do
    expect(roteiro.primeiro['id']).to eq('s1')
    expect(roteiro.entrar(roteiro.passo('s1'), 'entao')['id']).to eq('a1')
    expect(roteiro.seguinte('a1')['id']).to eq('a2')
    expect(roteiro.seguinte('a2')['id']).to eq('e1')
    expect(roteiro.seguinte('v1')).to be_nil
  end

  it 'ramo vazio segue para depois de quem o abriu' do
    expect(roteiro.entrar(roteiro.passo('s1'), 'senao')['id']).to eq('e1')
  end

  # F7 (#2500): os caminhos do "decidir" e o "nenhum se aplica" entram pela travessia única da Receita.
  it 'acha os passos dos caminhos e do nenhum e sai deles no passo depois do decidir', :aggregate_failures do
    decidir = { 'id' => 'd1', 'tipo' => 'decidir', 'caminhos' => [{ 'chave' => 'a', 'passos' => [{ 'id' => 'c1' }, { 'id' => 'c2' }] }],
                'nenhum' => [{ 'id' => 'n1' }] }
    com_decidir = described_class.new({ 'passos' => [decidir, { 'id' => 'fim' }] })

    expect(com_decidir.passo('c2')['id']).to eq('c2')
    expect(com_decidir.seguinte('c1')['id']).to eq('c2')
    expect(com_decidir.seguinte('c2')['id']).to eq('fim')
    expect(com_decidir.seguinte('n1')['id']).to eq('fim')
  end

  # G46 (o laço dos documentos): o caminho marcado no `de_novo` com `desde` volta ao "esperar até" de antes.
  describe 'o de_novo com desde' do
    let(:decide) do
      { 'id' => 'decide', 'tipo' => 'decidir',
        'caminhos' => [{ 'chave' => 'falta', 'passos' => [{ 'id' => 'pede' }] }, { 'chave' => 'ilegivel', 'passos' => [] },
                       { 'chave' => 'ok', 'passos' => [{ 'id' => 'move' }] }],
        'nenhum' => [], 'de_novo' => { 'caminhos' => %w[falta ilegivel nenhum], 'desde' => 'espera' } }
    end
    let(:receita) { { 'passos' => [{ 'id' => 'lista' }, { 'id' => 'espera', 'tipo' => 'esperar_ate' }, decide, { 'id' => 'fim' }] } }

    it 'o fim do caminho marcado volta ao desde; o vazio e o "nenhum" voltam direto', :aggregate_failures do
      expect(roteiro.seguinte('pede')['id']).to eq('espera')
      expect(roteiro.entrar_no_caminho(decide, 'ilegivel')['id']).to eq('espera')
      expect(roteiro.entrar_no_caminho(decide, 'nenhum')['id']).to eq('espera')
      expect(roteiro.volta(decide, 'falta')).to eq('espera')
    end

    it 'o caminho que não está marcado segue depois do decidir', :aggregate_failures do
      expect(roteiro.entrar_no_caminho(decide, 'ok')['id']).to eq('move')
      expect(roteiro.seguinte('move')['id']).to eq('fim')
      expect(roteiro.volta(decide, 'ok')).to be_nil
    end

    it 'no ensaio (voltar: false), o caminho marcado para no fim', :aggregate_failures do
      ensaio = described_class.new(receita, voltar: false)

      expect(ensaio.seguinte('pede')).to be_nil
      expect(ensaio.entrar_no_caminho(decide, 'ilegivel')).to be_nil
      expect(ensaio.seguinte('move')['id']).to eq('fim')
    end

    it 'sem desde (G31), o caminho marcado segue depois do decidir, como antes' do
      g31 = decide.merge('de_novo' => { 'caminhos' => %w[ilegivel], 'prazo' => { 'valor' => 24, 'unidade' => 'horas' } })

      expect(described_class.new({ 'passos' => [g31, { 'id' => 'fim' }] }).entrar_no_caminho(g31, 'ilegivel')['id']).to eq('fim')
    end

    it 'lista os irmãos anteriores do passo, do mais perto ao mais longe' do
      expect(roteiro.anteriores('decide').pluck('id')).to eq(%w[espera lista])
    end
  end
end
