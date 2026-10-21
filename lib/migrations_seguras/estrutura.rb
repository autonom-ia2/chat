# Retrato da estrutura do banco (#2024), lido pela API de introspecção do ActiveRecord e pelo catálogo do Postgres.
# Serve para comparar o banco antes e depois das migrations do lote, depois do down e com o schema.rb do PR. As
# colunas e índices vão por nome, não pela ordem: o schema.rb lista as colunas na ordem física, que muda conforme a
# máquina em que ele foi gerado, e isso não é diferença de estrutura.
class MigrationsSeguras::Estrutura
  TABELAS_DO_RAILS = %w[schema_migrations ar_internal_metadata].freeze

  def self.capturar(connection = ActiveRecord::Base.connection)
    new(connection).capturar
  end

  # Caminhos ("tabelas.contacts.colunas.email") em que os dois retratos diferem.
  def self.diferencas(antes, depois, caminho = [])
    return (antes == depois ? [] : [caminho.join('.')]) unless antes.is_a?(Hash) && depois.is_a?(Hash)

    (antes.keys | depois.keys).sort.flat_map { |chave| diferencas(antes[chave], depois[chave], caminho + [chave]) }
  end

  def initialize(connection)
    @connection = connection
  end

  def capturar
    {
      'extensoes' => @connection.extensions.sort,
      'tipos_enum' => @connection.enum_types.to_h { |nome, valores| [nome.to_s, Array(valores).map(&:to_s)] },
      'tabelas' => tabelas.index_with { |tabela| tabela(tabela) },
      'views' => @connection.views.sort,
      'funcoes' => funcoes,
      'gatilhos' => gatilhos
    }
  end

  private

  def tabelas
    (@connection.tables - TABELAS_DO_RAILS).sort
  end

  def tabela(nome)
    {
      'chave_primaria' => Array(@connection.primary_key(nome)).map(&:to_s),
      'colunas' => @connection.columns(nome).to_h { |coluna| [coluna.name, coluna_retrato(coluna)] },
      'indices' => @connection.indexes(nome).to_h { |indice| [indice.name, indice_retrato(indice)] },
      'chaves_estrangeiras' => @connection.foreign_keys(nome).to_h { |fk| [fk.name, chave_retrato(fk)] },
      'restricoes' => @connection.check_constraints(nome).to_h { |restricao| [restricao.name, restricao.expression] }
    }
  end

  def coluna_retrato(coluna)
    {
      'tipo' => coluna.sql_type,
      'tipo_base' => coluna.type.to_s,
      'limite' => coluna.limit,
      'precisao' => coluna.precision,
      'escala' => coluna.scale,
      'nulo' => coluna.null,
      'default' => coluna.default,
      'default_funcao' => coluna.default_function
    }
  end

  def indice_retrato(indice)
    {
      'colunas' => Array(indice.columns).map(&:to_s),
      'unico' => indice.unique,
      'where' => indice.where,
      'using' => indice.using.to_s,
      'opclasses' => indice.opclasses.as_json,
      'orders' => indice.orders.as_json,
      'include' => Array(indice.include).map(&:to_s),
      'valido' => indice.valid?
    }
  end

  def chave_retrato(chave)
    {
      'para' => chave.to_table,
      'coluna' => chave.column.to_s,
      'chave_primaria' => chave.primary_key.to_s,
      'on_delete' => chave.on_delete.to_s,
      'validada' => chave.validated?
    }
  end

  # Funções da aplicação no schema public (sem as de extensão, como pg_trgm e vector), com o md5 da definição: corpo
  # mudado aparece como diferença. A chave leva os argumentos, por causa de sobrecarga. Agregado fica de fora porque
  # pg_get_functiondef não o aceita.
  def funcoes
    @connection.select_rows(<<~SQL.squish).to_h
      SELECT p.oid::regprocedure::text, md5(pg_get_functiondef(p.oid)) FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public' AND p.prokind IN ('f', 'p')
        AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid = p.oid AND d.deptype = 'e')
      ORDER BY 1
    SQL
  end

  def gatilhos
    @connection.select_rows(<<~SQL.squish).to_h
      SELECT c.relname || '.' || t.tgname, md5(pg_get_triggerdef(t.oid)) FROM pg_trigger t
      JOIN pg_class c ON c.oid = t.tgrelid
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE NOT t.tgisinternal AND n.nspname = 'public'
      ORDER BY 1
    SQL
  end
end
