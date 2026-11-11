# #2414 G50 (#2682, item 2): o gatilho que acontece de novo enquanto a execução da mesma automação ainda espera no
# mesmo alvo. Com `se_repetir: comeca_outra` no gatilho, a Partida abre outra execução, marcada `paralela`: a 2ª falta
# do aluno (exemplo 4) começa a dela durante os 30 dias da 1ª.
#
# O índice da execução aberta (uma por automação, alvo e gatilho) passa a valer só para a execução não paralela: a
# receita sem `se_repetir` continua com uma aberta só. O índice do evento (idx_autonomia_automacao_execucoes_evento)
# fica como está e continua barrando o mesmo fato entregue duas vezes.
#
# A coluna nasce false em todas (default constante: sem reescrever a tabela). O índice novo tem outro nome porque os
# dois coexistem por um momento: ele entra e é conferido válido antes de o velho sair, os dois com CONCURRENTLY, sem
# transação. Não há instante sem um índice válido barrando a segunda execução aberta não paralela.
#
# Cada índice que entra (o novo no up, o velho no down):
# - já existe e é válido: fica como está;
# - existe e é inválido (CREATE INDEX CONCURRENTLY que caiu no meio): é apagado e refeito, porque o IF NOT EXISTS o
#   daria por pronto só pelo nome;
# - depois de criado, é conferido: se não ficou válido, a migration para com erro, e o índice que já estava fica.
# Só durante cada CREATE/DROP INDEX CONCURRENTLY o lock_timeout sobe para 15 min e o statement_timeout fica zerado (como
# no #2211, 20261108520000); os dois voltam no ensure.
#
# A volta recria o índice velho, que conta as paralelas: com uma paralela aberta ele não fica válido. Por isso o down
# confere antes e para com a contagem, sem tocar em índice nenhum; quem volta fecha as paralelas abertas primeiro.
class AddParalelaToAutonomiaAutomacaoExecucoes < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  TABELA = :autonomia_automacao_execucoes
  CHAVE = %i[automacao_id alvo_type alvo_id chave_gatilho].freeze
  VELHO = 'idx_autonomia_automacao_execucoes_abertas'.freeze
  NOVO = 'idx_autonomia_automacao_execucoes_abertas_unica'.freeze
  ONDE = { VELHO => 'finalizada_em IS NULL', NOVO => 'finalizada_em IS NULL AND paralela = false' }.freeze

  def up
    add_column TABELA, :paralela, :boolean, null: false, default: false unless column_exists?(TABELA, :paralela)
    trocar_indice(entra: NOVO, sai: VELHO)
  end

  def down
    abertas = paralelas_abertas
    raise "G50: #{abertas} execução(ões) paralela(s) aberta(s); feche-as antes de voltar esta migration" if abertas.positive?

    trocar_indice(entra: VELHO, sai: NOVO)
    remove_column TABELA, :paralela, if_exists: true
  end

  private

  # O índice que sai só sai depois de o que entra estar válido.
  def trocar_indice(entra:, sai:)
    criar_valido(entra)
    com_espera_longa { remove_index TABELA, name: sai, algorithm: :concurrently, if_exists: true }
  end

  def criar_valido(nome)
    return if valido?(nome) == true

    com_espera_longa do
      remove_index TABELA, name: nome, algorithm: :concurrently if valido?(nome) == false
      add_index TABELA, CHAVE, unique: true, where: ONDE.fetch(nome), name: nome, algorithm: :concurrently
    end
    raise "G50: o índice #{nome} foi criado, mas ficou inválido" unless valido?(nome) == true
  end

  def paralelas_abertas
    return 0 unless column_exists?(TABELA, :paralela)

    select_value("SELECT count(*) FROM #{TABELA} WHERE finalizada_em IS NULL AND paralela").to_i
  end

  def com_espera_longa
    anteriores = { 'lock_timeout' => select_value('SHOW lock_timeout'), 'statement_timeout' => select_value('SHOW statement_timeout') }
    safety_assured { execute "SET lock_timeout = '15min'; SET statement_timeout = 0" }
    yield
  ensure
    anteriores&.each { |nome, valor| safety_assured { execute "SET #{nome} = #{connection.quote(valor)}" } }
  end

  # true = existe e é válido; false = existe e é inválido; nil = não existe.
  def valido?(nome)
    select_value("SELECT i.indisvalid FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid WHERE c.relname = #{connection.quote(nome)}")
  end
end
