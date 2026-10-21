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

  def self.ler(texto)
    new(texto).estrutura
  end

  def initialize(texto)
    resultado = Prism.parse(texto)
    raise ArgumentError, "schema.rb não é Ruby válido: #{resultado.errors.first&.message}" if resultado.failure?

    @raiz = resultado.value
    @estrutura = { 'extensoes' => [], 'tipos_enum' => {}, 'tabelas' => {}, 'views' => [], 'funcoes' => [], 'gatilhos' => [] }
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

  def ler_comando(comando)
    return unless comando.is_a?(Prism::CallNode) && comando.receiver.nil?

    case comando.name
    when :create_table then ler_tabela(comando)
    when :enable_extension then @estrutura['extensoes'] << texto(argumentos(comando).first)
    when :create_enum then @estrutura['tipos_enum'][texto(argumentos(comando).first)] = valor(argumentos(comando)[1])
    when :add_foreign_key then ler_chave(comando)
    end
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
    when :check_constraint
      tabela['restricoes'][opcoes(linha).fetch('name')] = texto(argumentos(linha).first)
    else
      tabela['colunas'][texto(argumentos(linha).first)] = coluna(linha.name.to_s, opcoes(linha))
    end
  end

  def ler_indice(tabela, linha)
    opcoes = opcoes(linha)
    tabela['indices'][opcoes.fetch('name')] = { 'colunas' => valor(argumentos(linha).first), 'unico' => opcoes['unique'] == true }
  end

  def coluna(tipo, opcoes)
    medidas = %w[limit precision scale array].filter_map { |chave| "#{chave}=#{opcoes[chave].inspect}" if opcoes.key?(chave) }
    {
      'tipo' => ([tipo] + medidas).join(' '),
      'tipo_base' => tipo,
      'limite' => opcoes['limit'],
      'precisao' => opcoes['precision'],
      'escala' => opcoes['scale'],
      'nulo' => opcoes['null'] != false,
      'default' => opcoes['default']&.to_s,
      'default_funcao' => nil
    }
  end

  def ler_chave(comando)
    origem, destino = argumentos(comando).first(2).map { |argumento| texto(argumento) }
    opcoes = opcoes(comando)
    nome = opcoes['name'] || "#{destino}.#{opcoes['column']}"
    tabela = @estrutura['tabelas'][origem]
    tabela['chaves_estrangeiras'][nome] = { 'para' => destino } if tabela
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
    when Prism::StringNode, Prism::SymbolNode then node.unescaped
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
