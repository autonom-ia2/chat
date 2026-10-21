require 'rails_helper'

RSpec.describe MigrationsSeguras::Compatibilidade do
  def coluna(tipo: 'character varying', nulo: true, default: nil)
    { 'tipo' => tipo, 'nulo' => nulo, 'default' => default, 'default_funcao' => nil }
  end

  def tabela(colunas, indices: {}, chaves: {}, restricoes: {})
    { 'chave_primaria' => ['id'], 'colunas' => colunas, 'indices' => indices,
      'chaves_estrangeiras' => chaves, 'restricoes' => restricoes }
  end

  def estrutura(tabelas, extras = {})
    { 'extensoes' => ['pg_trgm'], 'tipos_enum' => {}, 'tabelas' => tabelas, 'views' => [], 'funcoes' => [],
      'gatilhos' => [] }.merge(extras)
  end

  let(:contatos) { tabela({ 'id' => coluna(tipo: 'bigint', nulo: false), 'email' => coluna, 'nome' => coluna }) }
  let(:antes) { estrutura('contacts' => contatos) }

  def verificar(depois, retiradas: {})
    described_class.new(antes: antes, depois: depois, retiradas: retiradas)
  end

  def onde(achados)
    achados.map(&:onde)
  end

  it 'aceita o que só acrescenta: coluna nula, coluna NOT NULL com default e tabela nova' do
    colunas = contatos['colunas'].merge('apelido' => coluna, 'ativo' => coluna(tipo: 'boolean', nulo: false, default: 'true'))
    depois = estrutura('contacts' => tabela(colunas), 'metas' => tabela({ 'id' => coluna(tipo: 'bigint', nulo: false) }))

    resultado = verificar(depois)

    expect(resultado).to be_compativel
    expect(resultado.avisos).to be_empty
  end

  it 'bloqueia coluna removida ou renomeada, que o código anterior ainda grava' do
    depois = estrutura('contacts' => tabela(contatos['colunas'].except('nome').merge('nome_completo' => coluna)))

    expect(onde(verificar(depois).bloqueios)).to eq(['contacts.nome'])
  end

  it 'aceita a remoção anunciada em db/retiradas.yml da base' do
    depois = estrutura('contacts' => tabela(contatos['colunas'].except('nome')))

    expect(verificar(depois, retiradas: { 'colunas' => ['contacts.nome'] })).to be_compativel
  end

  it 'bloqueia tabela removida, a não ser que esteja anunciada' do
    depois = estrutura({})

    expect(onde(verificar(depois).bloqueios)).to eq(['contacts'])
    expect(verificar(depois, retiradas: { 'tabelas' => ['contacts'] })).to be_compativel
  end

  it 'bloqueia troca de tipo e coluna existente que vira NOT NULL' do
    colunas = contatos['colunas'].merge('email' => coluna(nulo: false), 'nome' => coluna(tipo: 'text'))

    expect(onde(verificar(estrutura('contacts' => tabela(colunas))).bloqueios)).to contain_exactly('contacts.email', 'contacts.nome')
  end

  it 'bloqueia coluna nova NOT NULL sem default numa tabela que já existe' do
    colunas = contatos['colunas'].merge('documento' => coluna(nulo: false))

    expect(onde(verificar(estrutura('contacts' => tabela(colunas))).bloqueios)).to eq(['contacts.documento'])
  end

  it 'bloqueia view, extensão e valor de enum removidos' do
    antes['views'] = ['resumo']
    antes['tipos_enum'] = { 'situacao' => %w[aberta fechada] }
    depois = estrutura({ 'contacts' => contatos }, 'extensoes' => [], 'tipos_enum' => { 'situacao' => ['aberta'] })

    expect(onde(verificar(depois).bloqueios)).to contain_exactly('resumo', 'pg_trgm', 'situacao.fechada')
  end

  it 'só avisa índice único, chave estrangeira e restrição novos em tabela existente, e índice removido' do
    antes['tabelas']['contacts'] = tabela(contatos['colunas'], indices: { 'idx_nome' => { 'unico' => false } })
    depois = estrutura('contacts' => tabela(contatos['colunas'],
                                            indices: { 'idx_email' => { 'unico' => true } },
                                            chaves: { 'fk_conta' => {} },
                                            restricoes: { 'email_valido' => 'email <> \'\'' }))

    resultado = verificar(depois)

    expect(resultado).to be_compativel
    expect(onde(resultado.avisos)).to contain_exactly('contacts.idx_email', 'contacts.fk_conta',
                                                      'contacts.email_valido', 'contacts.idx_nome')
  end
end
