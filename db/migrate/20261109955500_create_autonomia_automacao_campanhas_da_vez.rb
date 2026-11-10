# #2414 G55 (exemplo 16): a campanha da vez num gatilho recorrente de card ou contato. Uma linha por automação, vez
# (a ocorrência do recorrente) e passo de campanha. A vez fecha pelo estado das execuções dela, lido do banco
# (CampanhaDaOcorrencia); aqui ficam só os lotes que a varredura enfileirou e os que já rodaram, a campanha que saiu,
# quando a vez fechou, a próxima conferência marcada (uma só por vez) e quantas vezes mandar deu erro.
#
# O índice nas execuções acha as execuções de uma vez pelo começo da marca (`evento LIKE 'recorrente:...:%'`) sem ler
# todas as da automação: `text_pattern_ops` porque o LIKE com prefixo não usa o índice comum fora da collation C.
# Concorrente, para não travar escrita nas execuções; por isso a migration roda fora de transação, e cada passo pode
# ser repetido. Como no #2211 (AddIndicesDaBuscaSemAcento): o índice válido fica; o inválido (CREATE CONCURRENTLY
# interrompido) é apagado e refeito, sem IF NOT EXISTS, e conferido depois; só durante o CREATE/DROP o lock_timeout sobe
# para 15 min e o statement_timeout fica zerado, e os dois voltam no ensure.
class CreateAutonomiaAutomacaoCampanhasDaVez < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  INDICE = 'idx_autonomia_automacao_execucoes_vez'.freeze

  def up
    create_table :autonomia_automacao_campanhas_da_vez, if_not_exists: true do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.references :automacao, null: false, foreign_key: { to_table: :autonomia_automacoes }, index: false
      t.string :ocorrencia, null: false
      t.string :passo, null: false
      t.integer :lotes
      t.jsonb :lotes_feitos, null: false, default: []
      t.integer :campanha_display_id
      t.datetime :fechada_em
      t.datetime :conferir_em
      t.integer :tentativas, null: false, default: 0
      t.timestamps
    end
    add_index :autonomia_automacao_campanhas_da_vez, %i[automacao_id ocorrencia passo],
              unique: true, name: 'idx_autonomia_automacao_campanhas_da_vez_unica', if_not_exists: true
    indice_da_vez
  end

  def down
    com_espera_longa { remove_index :autonomia_automacao_execucoes, name: INDICE, algorithm: :concurrently, if_exists: true }
    drop_table :autonomia_automacao_campanhas_da_vez, if_exists: true
  end

  private

  def indice_da_vez
    return if valido? == true

    com_espera_longa do
      remove_index :autonomia_automacao_execucoes, name: INDICE, algorithm: :concurrently if valido? == false
      add_index :autonomia_automacao_execucoes, %i[automacao_id evento], opclass: { evento: :text_pattern_ops },
                                                                         where: 'evento IS NOT NULL', name: INDICE,
                                                                         algorithm: :concurrently
    end
    raise "#2823: o índice #{INDICE} foi criado, mas ficou inválido" unless valido? == true
  end

  def com_espera_longa
    anteriores = { 'lock_timeout' => select_value('SHOW lock_timeout'), 'statement_timeout' => select_value('SHOW statement_timeout') }
    safety_assured { execute "SET lock_timeout = '15min'; SET statement_timeout = 0" }
    yield
  ensure
    anteriores&.each { |nome, valor| safety_assured { execute "SET #{nome} = #{connection.quote(valor)}" } }
  end

  # true = existe e é válido; false = existe e é inválido; nil = não existe.
  def valido?
    select_value("SELECT i.indisvalid FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid WHERE c.relname = #{connection.quote(INDICE)}")
  end
end
