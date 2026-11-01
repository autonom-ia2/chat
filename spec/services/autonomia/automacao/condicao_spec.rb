require 'rails_helper'

RSpec.describe Autonomia::Automacao::Condicao do
  let(:account) { create(:account) }
  let(:contato) { create(:contact, account: account, custom_attributes: { 'placa' => 'ABC1D23', 'renda' => '3500' }) }
  let(:conversa) { create(:conversation, account: account, contact: contato, status: :resolved) }
  let(:valores) { Autonomia::Automacao::Valores.new(conversa: conversa) }

  before { conversa.update_labels(%w[vip pos-venda]) }

  def verdadeira?(condicao) = described_class.new(condicao, valores).verdadeira?
  def campo(caminho, operacao, valor = nil) = { 'campo' => { '$valor' => caminho }, 'op' => operacao, 'valor' => valor }

  it 'compara igual e diferente' do
    expect(verdadeira?(campo('conversa.status', 'igual', 'resolved'))).to be(true)
    expect(verdadeira?(campo('conversa.status', 'diferente', 'resolved'))).to be(false)
  end

  it 'procura na lista de etiquetas' do
    expect(verdadeira?(campo('conversa.etiquetas', 'contem', 'vip'))).to be(true)
    expect(verdadeira?(campo('conversa.etiquetas', 'nao_contem', 'vip'))).to be(false)
  end

  it 'compara número, e dá falso quando um dos lados não é número' do
    expect(verdadeira?(campo('contato.atributos.renda', 'maior', 3000))).to be(true)
    expect(verdadeira?(campo('contato.atributos.renda', 'menor', 3000))).to be(false)
    expect(verdadeira?(campo('contato.atributos.placa', 'maior', 3000))).to be(false)
  end

  it 'trata valor ausente como vazio, sem erro' do
    expect(verdadeira?(campo('contato.atributos.cpf', 'vazio'))).to be(true)
    expect(verdadeira?(campo('contato.atributos.cpf', 'igual', 'x'))).to be(false)
    expect(verdadeira?(campo('contato.atributos.placa', 'preenchido'))).to be(true)
  end

  it 'junta com todas e alguma' do
    sim = campo('conversa.status', 'igual', 'resolved')
    nao = campo('conversa.etiquetas', 'contem', 'perdido')

    expect(verdadeira?({ 'todas' => [sim, nao] })).to be(false)
    expect(verdadeira?({ 'alguma' => [sim, nao] })).to be(true)
  end

  it 'lista os caminhos que lê, para o salvar conferir' do
    condicao = { 'todas' => [campo('conversa.status', 'vazio'), { 'alguma' => [campo('contato.nome', 'vazio')] }] }

    expect(described_class.caminhos(condicao)).to eq(%w[conversa.status contato.nome])
  end
end
