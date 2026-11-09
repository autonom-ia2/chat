# #2414 G50 (#2682, item 2): o gatilho que acontece de novo enquanto a execução da mesma automação ainda espera no
# mesmo alvo. Com `se_repetir: comeca_outra` no gatilho, a Partida abre outra execução, marcada `paralela`: a 2ª falta
# do aluno (exemplo 4) começa a dela durante os 30 dias da 1ª.
#
# O índice da execução aberta (uma por automação, alvo e gatilho) passa a valer só para a execução não paralela: a
# receita sem `se_repetir` continua com uma aberta só. O índice do evento (idx_autonomia_automacao_execucoes_evento)
# fica como está e continua barrando o mesmo fato entregue duas vezes.
#
# Aditiva. A coluna nasce false em todas (default constante: sem reescrever a tabela). O índice novo entra antes de o
# velho sair, os dois com CONCURRENTLY, sem transação: não há instante sem a garantia. O índice novo tem outro nome
# porque os dois coexistem por um momento.
class AddParalelaToAutonomiaAutomacaoExecucoes < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  TABELA = :autonomia_automacao_execucoes
  CHAVE = %i[automacao_id alvo_type alvo_id chave_gatilho].freeze
  VELHO = 'idx_autonomia_automacao_execucoes_abertas'.freeze
  NOVO = 'idx_autonomia_automacao_execucoes_abertas_unica'.freeze

  def up
    add_column TABELA, :paralela, :boolean, null: false, default: false unless column_exists?(TABELA, :paralela)
    add_index TABELA, CHAVE, unique: true, where: 'finalizada_em IS NULL AND paralela = false', name: NOVO,
                             algorithm: :concurrently, if_not_exists: true
    remove_index TABELA, name: VELHO, algorithm: :concurrently, if_exists: true
  end

  # A volta recria o índice velho: com duas execuções abertas no mesmo alvo ele falha, e quem volta fecha as
  # paralelas antes.
  def down
    add_index TABELA, CHAVE, unique: true, where: 'finalizada_em IS NULL', name: VELHO, algorithm: :concurrently, if_not_exists: true
    remove_index TABELA, name: NOVO, algorithm: :concurrently, if_exists: true
    remove_column TABELA, :paralela, if_exists: true
  end
end
