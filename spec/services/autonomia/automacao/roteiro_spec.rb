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
end
