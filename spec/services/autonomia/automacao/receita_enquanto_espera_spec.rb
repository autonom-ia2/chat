require 'rails_helper'

# O que o "esperar até" faz enquanto espera, conferido ao salvar (G63 #2830, G64 #2839): o galho "a cada mensagem do
# cliente" e a hora da conferência diária. O motor está em espera_no_executor_enquanto_espera_spec.rb.
RSpec.describe Autonomia::Automacao::Receita do
  let(:account) { create(:account) }
  let(:respondeu) { { 'campo' => { '$valor' => 'conversa.cliente_respondeu' }, 'op' => 'igual', 'valor' => true } }
  let(:urgente) { { 'campo' => { '$valor' => 'conversa.prioridade' }, 'op' => 'igual', 'valor' => 'urgent' } }

  def espera(id = 'espera', **campos)
    { 'id' => id, 'tipo' => 'esperar_ate', 'condicao' => urgente, 'prazo' => 'sem_prazo' }.merge(campos.stringify_keys)
  end

  def parar(id) = { 'id' => id, 'tipo' => 'parar' }

  def receita(*passos, gatilho: 'conversa.criada') = { 'gatilho' => { 'tipo' => gatilho }, 'passos' => passos }

  def problemas(dados) = described_class.new(dados, conta: account, account_user: nil).problemas

  def texto(chave, **valores) = I18n.t("autonomia.automacao.receita.#{chave}", **valores)

  it 'aceita a espera sem prazo com a hora da manhã e o galho', :aggregate_failures do
    dados = receita(espera(conferir_as: 8, a_cada_mensagem: [parar('g1')]))

    expect(described_class.esquema_valido?(dados)).to be(true)
    expect(problemas(dados)).to be_empty
  end

  it 'o esquema recusa hora fora de 0 a 23', :aggregate_failures do
    expect(described_class.esquema_valido?(receita(espera(conferir_as: 24)))).to be(false)
    expect(described_class.esquema_valido?(receita(espera(conferir_as: -1)))).to be(false)
    expect(described_class.esquema_valido?(receita(espera(conferir_as: 0)))).to be(true)
  end

  it 'recusa a hora da conferência com prazo de duração' do
    dados = receita(espera(prazo: { 'valor' => 2, 'unidade' => 'horas' }, conferir_as: 8))

    expect(problemas(dados)).to include(texto(:conferir_as_com_prazo, passo: 'espera'))
  end

  it 'recusa o galho dentro de outro galho' do
    dados = receita(espera(a_cada_mensagem: [espera('dentro', a_cada_mensagem: [parar('g2')])]))

    expect(problemas(dados)).to include(texto(:a_cada_aninhado, passo: 'dentro'))
  end

  it 'recusa o galho no gatilho da conta, que não tem cliente' do
    dados = receita({ 'id' => 'espera', 'tipo' => 'esperar_ate', 'condicao' => urgente, 'prazo' => { 'valor' => 1, 'unidade' => 'dias' },
                      'a_cada_mensagem' => [parar('g1')] }, gatilho: 'conta.recorrente')

    expect(problemas(dados)).to include(texto(:a_cada_sem_contato, passo: 'espera'))
  end

  it 'recusa o "voltar a esperar" (G46) que aponta para dentro do galho' do
    decidir = { 'id' => 'decide', 'tipo' => 'decidir', 'instrucao' => 'Decida',
                'caminhos' => [{ 'chave' => 'mais', 'nome' => 'Mais', 'descricao' => 'quer mais', 'passos' => [] },
                               { 'chave' => 'pronto', 'nome' => 'Pronto', 'descricao' => 'acabou', 'passos' => [] }],
                'de_novo' => { 'caminhos' => %w[mais], 'desde' => 'dentro' } }
    dentro = { 'id' => 'dentro', 'tipo' => 'esperar_ate', 'condicao' => respondeu, 'prazo' => { 'valor' => 1, 'unidade' => 'dias' } }
    dados = receita(espera(a_cada_mensagem: [dentro, decidir]))

    expect(problemas(dados)).to include(texto(:de_novo_desde_no_galho, passo: 'decide', desde: 'dentro'))
  end

  it 'anda pelo galho na travessia única: a ação de dentro dele é conferida' do
    proibida = { 'id' => 'x1', 'tipo' => 'acao', 'acao' => 'DELETE accounts/:id', 'descricao' => 'Apagar' }

    expect(problemas(receita(espera(a_cada_mensagem: [proibida])))).to include(texto(:acao_fora, passo: 'x1', acao: 'DELETE accounts/:id'))
  end
end
