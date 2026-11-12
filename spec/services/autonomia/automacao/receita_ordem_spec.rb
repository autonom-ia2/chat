require 'rails_helper'

# #2608: a Receita foi dividida em validadores por área sem mudar o que a pessoa lê. Uma receita com problemas de várias
# áreas (ids, gatilho, ação, condição, mensagem, IA, "esperar até") devolve as frases na ordem de sempre: primeiro o id
# repetido, depois o gatilho, depois cada passo na ordem em que aparece (com os ramos dentro do passo que os abre) e, no
# fim, o "esperar até" sem prazo que vence e o que ele faz enquanto espera.
RSpec.describe Autonomia::Automacao::Receita do
  let(:account) { create(:account) }
  let(:desconhecido) { 'contato.nao_existe' }
  let(:condicao) { { 'campo' => { '$valor' => desconhecido }, 'op' => 'igual', 'valor' => 'x' } }

  def frase(chave, **valores) = I18n.t("autonomia.automacao.receita.#{chave}", **valores)

  def receita
    mensagem = { 'id' => 'm1', 'tipo' => 'mensagem', 'texto' => ['Oi ', { '$valor' => desconhecido }] }
    { 'gatilho' => { 'tipo' => 'conversa.criada', 'filtros' => [condicao] },
      'passos' => [{ 'id' => 'a1', 'tipo' => 'acao', 'acao' => 'DELETE accounts/:id', 'descricao' => 'Apagar' },
                   { 'id' => 's1', 'tipo' => 'se', 'condicao' => condicao, 'entao' => [mensagem], 'senao' => [] },
                   { 'id' => 'w1', 'tipo' => 'escrever', 'le' => %w[mensagens_recentes], 'instrucao' => 'Agradeça.', 'destino' => 'nota' },
                   { 'id' => 'e1', 'tipo' => 'esperar_ate', 'condicao' => condicao, 'prazo' => 'sem_prazo',
                     'se_vencer' => [{ 'id' => 'v1', 'tipo' => 'parar' }] },
                   { 'id' => 'e2', 'tipo' => 'esperar_ate', 'condicao' => condicao, 'prazo' => { 'valor' => 1, 'unidade' => 'dias' },
                     'conferir_as' => '09:00' },
                   { 'id' => 'p1', 'tipo' => 'parar' }, { 'id' => 'p1', 'tipo' => 'parar' }] }
  end

  it 'devolve as frases de áreas diferentes na mesma ordem de antes da divisão' do
    problemas = described_class.new(receita, conta: account, account_user: nil).problemas

    expect(problemas).to eq([frase(:id_repetido, passo: 'p1'),
                             frase(:valor_desconhecido, passo: 'gatilho', caminho: desconhecido),
                             frase(:acao_fora, passo: 'a1', acao: 'DELETE accounts/:id'),
                             frase(:valor_desconhecido, passo: 's1', caminho: desconhecido),
                             frase(:passo_desligado, passo: 'm1'),
                             frase(:valor_desconhecido, passo: 'm1', caminho: desconhecido),
                             frase(:ia_desligada, passo: 'w1'),
                             frase(:valor_desconhecido, passo: 'e1', caminho: desconhecido),
                             frase(:valor_desconhecido, passo: 'e2', caminho: desconhecido),
                             frase(:sem_prazo_com_se_vencer, passo: 'e1'),
                             frase(:conferir_as_com_prazo, passo: 'e2')])
  end
end
