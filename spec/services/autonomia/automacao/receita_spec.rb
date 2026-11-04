require 'rails_helper'

# A travessia única da receita (#2500, F7): o salvar, o ligar e a chave de funis andam por todos os ramos, inclusive os
# caminhos do "decidir" e o "nenhum se aplica". Um ramo de fora deixaria a ação de dentro sem conferência.
RSpec.describe Autonomia::Automacao::Receita do
  let(:account) { create(:account) }
  let(:passo_proibido) { { 'id' => 'x1', 'tipo' => 'acao', 'acao' => 'DELETE accounts/:id', 'descricao' => 'Apagar' } }

  def decidir(caminho: [], nenhum: [])
    { 'id' => 'd1', 'tipo' => 'decidir',
      'caminhos' => [{ 'chave' => 'sinistro', 'descricao' => 'batida', 'passos' => caminho },
                     { 'chave' => 'cotacao', 'descricao' => 'preço', 'passos' => [] }],
      'nenhum' => nenhum }
  end

  def receita(*passos)
    { 'gatilho' => { 'tipo' => 'conversa.criada' }, 'passos' => passos }
  end

  it 'anda pelos ramos fixos, pelos caminhos do decidir e pelo nenhum, na ordem' do
    se = { 'id' => 's1', 'tipo' => 'se', 'entao' => [{ 'id' => 'e1' }], 'senao' => [{ 'id' => 'e2' }] }
    todos = described_class.new(receita(se, decidir(caminho: [{ 'id' => 'c1' }], nenhum: [{ 'id' => 'n1' }])), conta: account)

    expect(todos.passos.pluck('id')).to eq(%w[s1 e1 e2 d1 c1 n1])
  end

  it 'confere a ação de dentro de um caminho do decidir no salvar' do
    problemas = described_class.new(receita(decidir(caminho: [passo_proibido])), conta: account).problemas

    expect(problemas).to include(I18n.t('autonomia.automacao.receita.acao_fora', passo: 'x1', acao: 'DELETE accounts/:id'))
  end

  it 'confere a ação de dentro do nenhum se aplica no salvar' do
    problemas = described_class.new(receita(decidir(nenhum: [passo_proibido])), conta: account).problemas

    expect(problemas).to include(I18n.t('autonomia.automacao.receita.acao_fora', passo: 'x1', acao: 'DELETE accounts/:id'))
  end

  it 'recusa o id repetido entre um caminho e o nenhum' do
    repetido = decidir(caminho: [{ 'id' => 'p9', 'tipo' => 'parar' }], nenhum: [{ 'id' => 'p9', 'tipo' => 'parar' }])

    expect(described_class.new(receita(repetido), conta: account).problemas)
      .to include(I18n.t('autonomia.automacao.receita.id_repetido', passo: 'p9'))
  end

  it 'ignora só o caminho fora do formato, sem perder os outros' do
    torto = { 'id' => 'd1', 'tipo' => 'decidir', 'nenhum' => 'texto',
              'caminhos' => ['texto', { 'chave' => 'a' }, { 'chave' => 'b', 'passos' => [{ 'id' => 'x' }] }] }

    expect(described_class.ramos(torto)).to eq([[{ 'id' => 'x' }]])
  end
end
