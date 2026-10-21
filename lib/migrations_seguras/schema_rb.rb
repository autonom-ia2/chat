require 'digest'
require 'prism'

# Estrutura de um db/schema.rb lida pela árvore sintática do Ruby (Prism), sem banco (#2024).
#
# O deploy usa para comparar o schema.rb da blue com o do commit que vai subir, antes de a green rodar as migrations:
# a CI compara com a main, mas a blue pode estar vários PRs atrás. O formato é o da Estrutura (tabelas, colunas,
# índices...), para a mesma Compatibilidade decidir. Como os dois lados passam pelo mesmo leitor, o tipo é o nome do
# método do schema.rb (string, bigint) com limit/precision/scale, não o sql_type do banco.
# Ruby puro: o deploy roda isto sem o Rails.
class MigrationsSeguras::SchemaRb
  TIPOS_DA_CHAVE = { 'serial' => 'integer', 'bigserial' => 'bigint' }.freeze
  # Como o banco vê os inteiros: um tipo só, com o tamanho no limite. Assim integer -> bigint é "ganhou espaço",
  # igual ao que a Estrutura lê do banco.
  TAMANHO_DO_INTEIRO = { 'integer' => 4, 'bigint' => 8 }.freeze
  # Restrições de tabela que o schema.rb escreve dentro do create_table.
  RESTRICOES = %i[check_constraint unique_constraint exclusion_constraint].freeze

  def self.ler(texto)
    new(texto).estrutura
  end

  def initialize(texto)
    resultado = Prism.parse(texto)
    raise ArgumentError, "schema.rb não é Ruby válido: #{resultado.errors.first&.message}" if resultado.failure?

    @raiz = resultado.value
    @estrutura = { 'extensoes' => [], 'tipos_enum' => {}, 'tabelas' => {}, 'views' => [], 'funcoes' => {}, 'gatilhos' => {} }
  end

  def estrutura
    comandos.each { |comando| ler_comando(comando) }
    @estrutura['extensoes'].sort!
    @estrutura
  end

  private

  # Os comandos dentro do bloco de `ActiveRecord::Schema[x].define(version: ...) do ... end`.
  def comandos
    definicao = @raiz.statements.body.find { |node| node.is_a?(Prism::CallNode) && node.name == :define && node.block }
    raise ArgumentError, 'schema.rb sem ActiveRecord::Schema.define' unless definicao

    definicao.block.body&.body || []
  end

  LEITORES = { create_table: :ler_tabela, enable_extension: :ler_extensao, create_enum: :ler_enum,
               add_foreign_key: :ler_chave, execute: :ler_sql }.freeze

  def ler_comando(comando)
    return unless comando.is_a?(Prism::CallNode)
    return ler_gatilho_encadeado(comando) if comando.receiver

    leitor = LEITORES[comando.name]
    send(leitor, comando) if leitor
  end

  # `create_trigger("nome").on("tabela").after(:insert).for_each(:row) do ... end` (hairtrigger): a chamada de fora tem
  # receptor; o create_trigger fica na raiz da cadeia.
  def ler_gatilho_encadeado(comando)
    raiz = comando
    raiz = raiz.receiver while raiz.receiver.is_a?(Prism::CallNode)
    return unless raiz.name == :create_trigger && raiz.receiver.nil?

    @estrutura['gatilhos']["create_trigger #{texto(argumentos(raiz).first)}"] = Digest::MD5.hexdigest(comando.slice)
  end

  def ler_extensao(comando)
    @estrutura['extensoes'] << texto(argumentos(comando).first)
  end

  def ler_enum(comando)
    @estrutura['tipos_enum'][texto(argumentos(comando).first)] = valor(argumentos(comando)[1])
  end

  def ler_tabela(comando)
    nome = texto(argumentos(comando).first)
    opcoes = opcoes(comando)
    tabela = { 'chave_primaria' => [], 'colunas' => {}, 'indices' => {}, 'chaves_estrangeiras' => {}, 'restricoes' => {} }
    ler_chave_primaria(tabela, opcoes)
    corpo = comando.block&.body&.body || []
    corpo.each { |linha| ler_linha(tabela, linha) if linha.is_a?(Prism::CallNode) }
    @estrutura['tabelas'][nome] = tabela
  end

  def ler_chave_primaria(tabela, opcoes)
    return if opcoes['id'] == false

    nome = (opcoes['primary_key'] || 'id').to_s
    tipo = opcoes['id'].is_a?(String) ? opcoes['id'] : 'bigint'
    tabela['chave_primaria'] = [nome]
    tabela['colunas'][nome] = coluna(TIPOS_DA_CHAVE.fetch(tipo, tipo), 'null' => false)
  end

  def ler_linha(tabela, linha)
    case linha.name
    when :index then ler_indice(tabela, linha)
    when *RESTRICOES
      tabela['restricoes'][opcoes(linha)['name'] || linha.slice] = texto(argumentos(linha).first)
    else
      tabela['colunas'][texto(argumentos(linha).first)] = coluna(linha.name.to_s, opcoes(linha))
    end
  end

  # Colunas, unicidade e o resto da definição (where, using, opclass, order): índice de mesmo nome que mudou aparece.
  def ler_indice(tabela, linha)
    opcoes = opcoes(linha)
    tabela['indices'][opcoes.fetch('name')] = opcoes.except('name').merge(
      'colunas' => valor(argumentos(linha).first), 'unico' => opcoes['unique'] == true
    )
  end

  # Os `execute` do schema.rb são as funções e os gatilhos (hairtrigger), quase sempre em heredoc. A chave é a primeira
  # linha do SQL (CREATE OR REPLACE FUNCTION public.x() / CREATE TRIGGER x ...) e o valor é o md5 do SQL inteiro: some
  # ou muda, a Compatibilidade avisa, como faz com o que o banco perde.
  def ler_sql(comando)
    sql = texto(argumentos(comando).first)
    cabeca = sql.lines.map(&:strip).find { |linha| !linha.empty? }.to_s
    grupo = cabeca.start_with?('CREATE OR REPLACE FUNCTION', 'CREATE FUNCTION') ? 'funcoes' : 'gatilhos'
    @estrutura[grupo][cabeca] = Digest::MD5.hexdigest(sql)
  end

  def coluna(tipo, opcoes)
    tipo_base, limite = medida_do_tipo(tipo, opcoes)
    medidas = %w[precision scale array].filter_map { |chave| "#{chave}=#{opcoes[chave].inspect}" if opcoes.key?(chave) }
    medidas.unshift("limit=#{limite.inspect}") unless limite.nil?
    {
      'tipo' => ([tipo_base] + medidas).join(' '),
      'tipo_base' => tipo_base,
      'limite' => limite,
      'precisao' => opcoes['precision'],
      'escala' => opcoes['scale'],
      'nulo' => opcoes['null'] != false,
      'default' => opcoes['default']&.to_s,
      'default_funcao' => nil
    }
  end

  def medida_do_tipo(tipo, opcoes)
    return [tipo, opcoes['limit']] unless TAMANHO_DO_INTEIRO.key?(tipo)

    ['integer', opcoes['limit'] || TAMANHO_DO_INTEIRO.fetch(tipo)]
  end

  def ler_chave(comando)
    origem, destino = argumentos(comando).first(2).map { |argumento| texto(argumento) }
    opcoes = opcoes(comando)
    coluna = opcoes['column'] || "#{singular(destino)}_id"
    nome = opcoes['name'] || "#{destino}.#{Array(coluna).join(',')}"
    tabela = @estrutura['tabelas'][origem]
    tabela['chaves_estrangeiras'][nome] = { 'para' => destino } if tabela
  end

  # O schema.rb só escreve column: quando ela foge do padrão do Rails (<destino no singular>_id). Sem o Rails aqui, o
  # singular cobre as formas das tabelas do fork (accounts, companies, addresses). Errar o singular de um nome raro não
  # cria falso alarme: a chave só precisa ser a mesma nas duas leituras de schema.rb, a da blue e a deste commit.
  def singular(tabela)
    return "#{tabela.delete_suffix('ies')}y" if tabela.end_with?('ies')
    return tabela.delete_suffix('es') if tabela.end_with?('sses')
    return tabela.delete_suffix('s') if tabela.end_with?('s') && !tabela.end_with?('ss')

    tabela
  end

  def argumentos(chamada)
    (chamada.arguments&.arguments || []).reject { |argumento| argumento.is_a?(Prism::KeywordHashNode) }
  end

  def opcoes(chamada)
    hash = (chamada.arguments&.arguments || []).find { |argumento| argumento.is_a?(Prism::KeywordHashNode) }
    return {} unless hash

    hash.elements.to_h { |par| [texto(par.key), valor(par.value)] }
  end

  def texto(node)
    case node
    # Chamada sem argumento (o Rails não escreve, mas um schema.rb editado à mão pode): o erro diz onde.
    when nil then raise ArgumentError, 'schema.rb com comando sem o argumento esperado (nome da tabela, coluna ou SQL)'
    when Prism::StringNode, Prism::SymbolNode then node.unescaped
    # Heredoc com interpolação: o slice seria só o `<<-SQL`.
    when Prism::InterpolatedStringNode then node.parts.map { |parte| texto(parte) }.join
    else node.slice
    end
  end

  # Valor de uma opção. Lambda de default (`-> { "now()" }`) e o que não é literal ficam como o código-fonte: os dois
  # schema.rb passam pelo mesmo leitor, então o texto basta para comparar.
  def valor(node)
    case node
    when Prism::TrueNode then true
    when Prism::FalseNode then false
    when Prism::NilNode then nil
    when Prism::IntegerNode then node.value
    when Prism::ArrayNode then node.elements.map { |elemento| valor(elemento) }
    else texto(node)
    end
  end
end
