require 'rails_helper'

# Os passos de IA (#2500, F7) no salvar: o esquema dos quatro passos e as conferências da Receita. A execução entra
# noutro PR; aqui só a forma.
RSpec.describe Autonomia::Automacao::Receita do
  let(:account) { create(:account) }
  let(:le) { %w[mensagens_recentes] }

  def caminho(nome, chave, passos = [])
    { 'nome' => nome, 'chave' => chave, 'descricao' => "quando #{nome}", 'passos' => passos }
  end

  def decidir(caminhos = [caminho('Sinistro', 'sinistro'), caminho('Cotação', 'cotacao')])
    { 'id' => 'd1', 'tipo' => 'decidir', 'le' => le, 'pergunta' => 'Sobre o que é?', 'caminhos' => caminhos, 'nenhum' => [] }
  end

  def extrair(campos)
    { 'id' => 'x1', 'tipo' => 'extrair', 'le' => le, 'campos' => campos }
  end

  def escrever(destino)
    { 'id' => 'w1', 'tipo' => 'escrever', 'le' => le, 'instrucao' => 'Agradeça o contato.', 'destino' => destino }
  end

  def resumir(destino)
    { 'id' => 'r1', 'tipo' => 'resumir', 'le' => le, 'linhas' => 3, 'destino' => destino }
  end

  def receita(*passos)
    { 'gatilho' => { 'tipo' => 'conversa.criada' }, 'passos' => passos }
  end

  def problemas(*passos)
    described_class.new(receita(*passos), conta: account).problemas
  end

  def erro(chave, **valores)
    I18n.t("autonomia.automacao.receita.#{chave}", **valores)
  end

  before { account.enable_features!('automacao_fundacao', 'automacao_motor', 'automacao_mensagens', 'automacao_ia') }

  it 'aceita os quatro passos no esquema' do
    create(:custom_attribute_definition, account: account, attribute_key: 'placa', attribute_model: 'conversation_attribute')
    campo = { 'chave' => 'placa', 'descricao' => 'a placa', 'destino' => 'conversa.atributos.placa' }
    quatro = [decidir, extrair([campo]), escrever('mensagem'), escrever('sugestao'), resumir('nota'),
              resumir({ 'avisar' => { 'responsavel' => true } })]
    passos = quatro.each_with_index.map { |passo, indice| passo.merge('id' => "p#{indice}") }

    expect(described_class.esquema_valido?(receita(*passos))).to be(true)
    expect(problemas(*passos)).to eq([])
  end

  it 'recusa o caminho sem nome à vista no esquema' do
    sem_nome = decidir([caminho('Sinistro', 'sinistro'), caminho('Cotação', 'cotacao').except('nome')])

    expect(described_class.esquema_valido?(receita(sem_nome))).to be(false)
  end

  it 'recusa passo de IA com a flag da F7 desligada' do
    account.disable_features!('automacao_ia')

    expect(problemas(decidir)).to include(erro(:ia_desligada, passo: 'd1'))
  end

  it 'recusa o escrever ao cliente e o resumo em aviso sem a flag de mensagens, e aceita a sugestão e a nota' do
    account.disable_features!('automacao_mensagens')

    expect(problemas(escrever('mensagem'))).to include(erro(:passo_desligado, passo: 'w1'))
    expect(problemas(resumir({ 'avisar' => { 'responsavel' => true } }))).to include(erro(:passo_desligado, passo: 'r1'))
    expect(problemas(escrever('sugestao'), resumir('nota'))).to eq([])
  end

  it 'mostra o nome do caminho quando dois nomes viram a mesma chave' do
    repetidos = decidir([caminho('Cotação', 'cotacao'), caminho('cotacao', 'cotacao')])

    expect(problemas(repetidos)).to eq([erro(:caminho_repetido, passo: 'd1', nome: 'Cotação')])
  end

  it 'recusa o dado repetido e o destino que a conta não tem' do
    campos = [{ 'chave' => 'placa', 'descricao' => 'a', 'destino' => 'contato.nome' },
              { 'chave' => 'placa', 'descricao' => 'b', 'destino' => 'conversa.atributos.nao_existe' },
              { 'chave' => 'cpf', 'descricao' => 'c', 'destino' => 'contato.email' }]

    expect(problemas(extrair(campos))).to contain_exactly(
      erro(:campo_repetido, passo: 'x1', chave: 'placa'),
      erro(:destino_invalido, passo: 'x1', destino: 'conversa.atributos.nao_existe'),
      erro(:destino_invalido, passo: 'x1', destino: 'contato.email')
    )
  end

  it 'confere o time de fora no resumo em aviso' do
    de_fora = create(:team)

    expect(problemas(resumir({ 'avisar' => { 'times' => [de_fora.id] } }))).to include(erro(:time_de_fora, passo: 'r1', id: de_fora.id))
  end
end
