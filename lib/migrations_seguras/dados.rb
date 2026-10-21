require 'prism'

# A migration mexe em DADOS? (#2024) Lida pela árvore sintática do Ruby (Prism), sem rodar nada.
#
# O job "Migrations do lote" confere estrutura: compatibilidade com o código anterior, down e schema.rb. Ele não sabe
# se um UPDATE apagou o que não devia, nem se um backfill vai levar minutos numa tabela grande. Migration que chama
# model, update_all e afins, connection.execute/exec_query ou SQL bruto sai marcada no relatório: revisão humana.
# Não bloqueia (ligar flag de conta nova é migration de dados legítima) e não é barreira contra perda de dados.
class MigrationsSeguras::Dados
  # Métodos que leem ou gravam linhas, chamados no model, na connection ou direto na migration.
  METODOS_DE_DADOS = %i[
    execute exec_query exec_update exec_delete exec_insert select_all select_one select_value select_values select_rows
    update_all delete_all destroy_all insert_all insert_all! upsert_all update_columns update_column update! save!
    create! create destroy find_each find_in_batches in_batches
  ].freeze
  # Constantes que aparecem em migration de schema sem tocar em dado.
  CONSTANTES_DE_SCHEMA = %w[ActiveRecord Rails].freeze

  def self.motivos(caminho)
    new(File.read(caminho)).motivos
  end

  def initialize(codigo)
    @raiz = Prism.parse(codigo).value
    @motivos = []
  end

  def motivos
    metodos_da_migration.each { |metodo| visitar(metodo.body) }
    @motivos.uniq
  end

  private

  # Só o corpo dos métodos (up, down, change, auxiliares): o `require` no topo do arquivo não conta.
  def metodos_da_migration
    encontrados = []
    pendentes = [@raiz]
    until pendentes.empty?
      node = pendentes.shift
      node.is_a?(Prism::DefNode) ? encontrados << node : pendentes.concat(node.compact_child_nodes)
    end
    encontrados
  end

  def visitar(node)
    return unless node

    registrar(node) if node.is_a?(Prism::CallNode)
    node.compact_child_nodes.each { |filho| visitar(filho) }
  end

  def registrar(chamada)
    @motivos << "#{chamada.name} (SQL ou linhas)" if METODOS_DE_DADOS.include?(chamada.name)
    constante = nome_da_constante(chamada.receiver)
    @motivos << "chama #{constante}" if constante && CONSTANTES_DE_SCHEMA.exclude?(constante.split('::').first)
  end

  def nome_da_constante(node)
    case node
    when Prism::ConstantReadNode then node.name.to_s
    when Prism::ConstantPathNode then node.slice
    end
  end
end
