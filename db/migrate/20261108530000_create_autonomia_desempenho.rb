# Painel de desempenho do agente (#2251, épico #2226): a leitura das conversas guardada no banco da conta.
#
# - autonomia_desempenho_fichas: a ficha do agente (sujeito = agente nosso ou robô de outro sistema), uma linha por
#   versão. `catalogo` são os nomes (temas, marcos, motivos, regras, resultados, origens, quem, cortes); `configuracao`
#   é a regra das contas (pedidos de compra, funil, comparações, horário, quem escreve pelo agente); `referencias` é o
#   que a conferência e o histórico deram uma vez (valor típico da venda, conferência, conversas de exemplo). Colunas
#   `json`, não `jsonb`: a ordem das chaves é a da ficha e desempata rankings (o jsonb reordena).
# - autonomia_desempenho_leituras: até onde cada conversa foi lida e com que versão da ficha. É a fila da atualização
#   automática (Issue própria): conversa com mensagem depois de `lida_ate_em` volta a ser lida.
# - autonomia_desempenho_procuras: uma linha por procura lida (o assunto da conversa, cortado quando o assunto muda),
#   com os campos de filtro em coluna e o resto em `dados`.
# - autonomia_desempenho_recomendacoes: as sugestões de "Do sinal à ação" de cada período, em cache (geradas fora,
#   nesta fase).
#
# `lote` marca de onde a linha veio (a carga inicial, a leitura automática): o rollback de uma carga apaga só o lote
# dela. Apagar a conta ou a conversa apaga a leitura pela chave estrangeira; o Autonomia::ExclusaoDaConta também lista
# as quatro tabelas. Tabelas novas e vazias: os índices nascem junto.
class CreateAutonomiaDesempenho < ActiveRecord::Migration[7.2]
  SUJEITOS = "sujeito_type::text = ANY ('{agente,robo}'::text[])".freeze

  def change
    create_fichas
    create_leituras
    create_procuras
    create_recomendacoes
  end

  private

  def create_fichas
    create_table :autonomia_desempenho_fichas do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :sujeito_type, null: false
      t.bigint :sujeito_id, null: false
      t.integer :versao, null: false
      t.json :catalogo, null: false
      t.json :configuracao, null: false
      t.json :referencias, null: false
      t.text :chave_de_leitura
      t.string :instrucao_hash
      t.string :lote, null: false
      t.timestamps
    end
    add_index :autonomia_desempenho_fichas, %i[account_id sujeito_type sujeito_id versao],
              unique: true, name: 'idx_autonomia_desempenho_fichas_versao'
    add_check_constraint :autonomia_desempenho_fichas, SUJEITOS, name: 'autonomia_desempenho_fichas_sujeito'
  end

  def create_leituras
    create_table :autonomia_desempenho_leituras do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :sujeito_type, null: false
      t.bigint :sujeito_id, null: false
      t.references :conversation, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.datetime :lida_ate_em, null: false
      t.integer :versao_ficha, null: false
      t.string :status, null: false
      t.string :lote, null: false
      t.timestamps
    end
    add_index :autonomia_desempenho_leituras, %i[account_id sujeito_type sujeito_id conversation_id],
              unique: true, name: 'idx_autonomia_desempenho_leituras_conversa'
    add_check_constraint :autonomia_desempenho_leituras, SUJEITOS, name: 'autonomia_desempenho_leituras_sujeito'
    add_check_constraint :autonomia_desempenho_leituras, "status::text = ANY ('{lida,lida_em_parte,minima,nao_lida}'::text[])",
                         name: 'autonomia_desempenho_leituras_status'
  end

  def create_procuras # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    create_table :autonomia_desempenho_procuras do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :sujeito_type, null: false
      t.bigint :sujeito_id, null: false
      t.references :conversation, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.integer :ordem, null: false
      t.datetime :inicio_em, null: false
      t.datetime :fim_em, null: false
      t.integer :versao_ficha, null: false
      t.boolean :teste, null: false, default: false
      t.string :pedido_id
      t.string :tema_id
      t.string :resultado_id
      t.string :qualidade_id
      t.string :origem_id
      t.string :quem_id
      t.string :anuncio_id
      t.string :marcos, array: true, null: false, default: []
      t.string :motivo_ids, array: true, null: false, default: []
      t.string :regra_ids, array: true, null: false, default: []
      t.boolean :perda_evitavel, null: false, default: false
      t.boolean :precisava_pessoa, null: false, default: false
      t.boolean :teve_pessoa, null: false, default: false
      t.jsonb :dados, null: false, default: {}
      t.string :lote, null: false
      t.timestamps
    end
    # Sem sujeito_type: o strong_migrations recusa índice não único com mais de 3 colunas, e o id do sujeito já estreita.
    add_index :autonomia_desempenho_procuras, %i[account_id sujeito_id inicio_em], name: 'idx_autonomia_desempenho_procuras_inicio'
    add_index :autonomia_desempenho_procuras, %i[account_id sujeito_type sujeito_id conversation_id ordem],
              unique: true, name: 'idx_autonomia_desempenho_procuras_ordem'
    add_check_constraint :autonomia_desempenho_procuras, SUJEITOS, name: 'autonomia_desempenho_procuras_sujeito'
  end

  def create_recomendacoes
    create_table :autonomia_desempenho_recomendacoes do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :sujeito_type, null: false
      t.bigint :sujeito_id, null: false
      t.string :periodo, null: false
      t.date :inicio, null: false
      t.date :fim, null: false
      t.integer :versao_ficha, null: false
      t.jsonb :cartoes, null: false, default: []
      t.datetime :gerada_em, null: false
      t.string :lote, null: false
      t.timestamps
    end
    add_index :autonomia_desempenho_recomendacoes, %i[account_id sujeito_type sujeito_id periodo],
              unique: true, name: 'idx_autonomia_desempenho_recomendacoes_periodo'
    add_check_constraint :autonomia_desempenho_recomendacoes, SUJEITOS, name: 'autonomia_desempenho_recomendacoes_sujeito'
    add_check_constraint :autonomia_desempenho_recomendacoes, "periodo::text = ANY ('{7,30,90,tudo}'::text[])",
                         name: 'autonomia_desempenho_recomendacoes_periodo'
  end
end
