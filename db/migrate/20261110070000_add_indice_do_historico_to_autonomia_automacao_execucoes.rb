# #2507: o histórico da automação ("O que aconteceu", #2505) ordena as execuções dela por `created_at desc` com offset,
# e a contagem da semana filtra por `automacao_id` e `created_at`. Só havia índice em `automacao_id`: as duas leituras
# ordenavam e filtravam todas as execuções da automação (sem teto de uso, uma de boas-vindas numa conta grande junta
# muitas em 90 dias). O índice (automacao_id, created_at) atende as duas.
#
# Concorrente, para não travar a escrita nas execuções; por isso a migration roda fora de transação, e pode ser
# repetida. Como no #2211 e no G55 (20261109955500): o índice válido fica; o inválido (CREATE CONCURRENTLY interrompido)
# é apagado e refeito, sem IF NOT EXISTS, que o daria por pronto só pelo nome, e é conferido depois; só durante o
# CREATE/DROP o lock_timeout sobe para 15 min e o statement_timeout fica zerado, e os dois voltam no ensure.
#
# O índice de `automacao_id` sozinho fica: a chave estrangeira e as outras leituras continuam com ele.
class AddIndiceDoHistoricoToAutonomiaAutomacaoExecucoes < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  TABELA = :autonomia_automacao_execucoes
  INDICE = 'idx_autonomia_automacao_execucoes_historico'.freeze

  def up
    return if valido? == true

    com_espera_longa do
      remove_index TABELA, name: INDICE, algorithm: :concurrently if valido? == false
      add_index TABELA, %i[automacao_id created_at], name: INDICE, algorithm: :concurrently
    end
    raise "#2507: o índice #{INDICE} foi criado, mas ficou inválido" unless valido? == true
  end

  def down
    com_espera_longa { remove_index TABELA, name: INDICE, algorithm: :concurrently, if_exists: true }
  end

  private

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
