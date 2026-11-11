# Vitrine de ferramentas prontas, F5 (#2858): as bases que a plataforma baixa e mantém atualizadas.
# - `autonomia_prontas_bases`: o estado de cada base (uma linha por base): a geração que vale para a busca, quando ela
#   foi atualizada, quantas linhas tem e a última falha. É daqui que sai o "atualizado em…" do cartão.
# - uma tabela por base, sem conta (o dado é público e igual para todas): operadoras de plano de saúde (ANS), aeronaves
#   (RAB da ANAC), geração distribuída (ANEEL, já somada por CEP), transportadores (RNTRC da ANTT) e focos de queimada
#   (INPE). Cada linha leva a `geracao`: a importação grava a geração nova ao lado da que vale, troca o número no estado
#   (uma linha, atômica) e só então apaga a antiga. A busca nunca fica vazia.
# Nenhum CPF e nenhum nome de pessoa física é gravado (ver docs/ferramentas-prontas/termos-das-fontes.md).
# As tabelas das bases não têm created_at/updated_at: são carregadas em massa pelo COPY, e quando cada geração entrou
# fica no `Estado` (`atualizado_em`).
# Só aditiva: seis tabelas novas. Nada é lido nem baixado sem a flag `agente_ferramentas_prontas_bases`. O down remove
# as seis.
# rubocop:disable Rails/CreateTableWithTimestamps
class CreateFerramentasProntasBases < ActiveRecord::Migration[7.2]
  def change
    criar_estado
    criar_operadoras
    criar_aeronaves
    criar_geracao_distribuida
    criar_transportadores
    criar_focos
  end

  private

  def criar_estado
    create_table :autonomia_prontas_bases do |t|
      t.string :base, null: false
      t.integer :geracao_ativa
      t.datetime :atualizado_em
      t.integer :linhas, null: false, default: 0
      t.datetime :tentado_em
      t.datetime :falhou_em
      t.string :motivo_da_falha
      t.timestamps
    end
    add_index :autonomia_prontas_bases, :base, unique: true, name: 'idx_prontas_bases_base'
  end

  def criar_operadoras
    create_table :autonomia_prontas_operadoras_ans do |t|
      t.integer :geracao, null: false
      t.string :registro_ans, null: false
      t.string :cnpj
      t.string :razao_social
      t.string :nome_fantasia
      t.string :nome_busca
      t.string :modalidade
      t.string :cidade
      t.string :uf
      t.date :registrada_em
      t.boolean :ativa, null: false, default: true
      t.date :cancelada_em
      t.string :motivo_do_cancelamento
    end
    add_index :autonomia_prontas_operadoras_ans, %i[geracao registro_ans], name: 'idx_prontas_operadoras_registro'
    add_index :autonomia_prontas_operadoras_ans, %i[geracao cnpj], name: 'idx_prontas_operadoras_cnpj'
  end

  def criar_aeronaves
    create_table :autonomia_prontas_aeronaves do |t|
      t.integer :geracao, null: false
      t.string :matricula, null: false
      t.jsonb :dados, null: false, default: {}
    end
    add_index :autonomia_prontas_aeronaves, %i[geracao matricula], name: 'idx_prontas_aeronaves_matricula'
  end

  def criar_geracao_distribuida
    create_table :autonomia_prontas_geracao_distribuida do |t|
      t.integer :geracao, null: false
      t.string :cep
      t.string :codigo_municipio
      t.string :uf
      t.string :tipo, null: false
      t.string :classe
      t.integer :quantidade, null: false, default: 0
      t.decimal :potencia_kw, precision: 14, scale: 2, null: false, default: 0
    end
    add_index :autonomia_prontas_geracao_distribuida, %i[geracao cep], name: 'idx_prontas_gd_cep'
    add_index :autonomia_prontas_geracao_distribuida, %i[geracao codigo_municipio], name: 'idx_prontas_gd_municipio'
  end

  def criar_transportadores
    create_table :autonomia_prontas_transportadores do |t|
      t.integer :geracao, null: false
      t.string :rntrc, null: false
      t.string :cnpj
      t.string :nome
      t.string :nome_busca
      t.string :categoria, null: false
      t.string :situacao, null: false
      t.string :municipio
      t.string :uf
      t.date :cadastrado_em
      t.date :situacao_desde
      t.boolean :equiparado # rubocop:disable Rails/ThreeStateBooleanColumn -- vazio = a ANTT não informou
    end
    add_index :autonomia_prontas_transportadores, %i[geracao rntrc], name: 'idx_prontas_transportadores_rntrc'
    add_index :autonomia_prontas_transportadores, %i[geracao cnpj], name: 'idx_prontas_transportadores_cnpj', where: 'cnpj IS NOT NULL'
    # A busca pelo nome, pelo começo das palavras (`nome_busca` começa com espaço: LIKE '% palavra%'), no índice de trigramas.
    add_index :autonomia_prontas_transportadores, :nome_busca,
              name: 'idx_prontas_transportadores_nome', using: :gin, opclass: :gin_trgm_ops, where: 'nome_busca IS NOT NULL'
  end

  def criar_focos
    create_table :autonomia_prontas_focos_queimada do |t|
      t.integer :geracao, null: false
      t.datetime :detectado_em, null: false
      t.decimal :latitude, precision: 9, scale: 5, null: false
      t.decimal :longitude, precision: 9, scale: 5, null: false
      t.string :codigo_municipio
      t.string :bioma
      t.string :satelite
    end
    add_index :autonomia_prontas_focos_queimada, %i[geracao codigo_municipio detectado_em], name: 'idx_prontas_focos_municipio'
    add_index :autonomia_prontas_focos_queimada, %i[geracao latitude], name: 'idx_prontas_focos_latitude'
  end
end
# rubocop:enable Rails/CreateTableWithTimestamps
