# Automação livre F9.2(a) (#2568, épico #2414; desenho em docs/automacao/F9-conversao-do-antigo.md, seção 5).
#
# - autonomia_automacao_conversoes: o par "regra antiga → automação nova" e o backup da linha antiga. Mínima, por
#   decisão do Rodrigo (05/11): o índice único (account_id, antigo_tipo, antigo_id) é a própria trava (uma antiga tem
#   no máximo uma conversão vigente) e é o que o motor antigo consulta; definicao_id é o que o motor novo consulta. O
#   created_at é o instante da conversão. A reversão apaga a linha.
# - o CHECK das execuções ganha o estado terminal `do_antigo`: a execução que o motor antigo grava para reivindicar um
#   fato no índice único (automacao_id, evento), e assim os dois motores nunca agem sobre o mesmo fato (seção 5.1).
#
# Sem transação: o CHECK novo entra NOT VALID (trava curta) e é validado depois, sem barrar escrita. O novo aceita
# tudo o que o antigo aceitava, então a validação não acha linha ruim. O down recusa, antes de mexer em
# qualquer coisa, enquanto houver `do_antigo`.
class CreateAutonomiaAutomacaoConversoes < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  CHECK = 'chk_autonomia_automacao_execucoes_finalizada'.freeze
  # Na forma que o Postgres devolve (ver CreateAutonomiaAutomacoes::FINALIZADA): a CI compara o dump com o schema.rb.
  FINALIZADA_ANTES = "((estado)::text = ANY (ARRAY['concluida'::text, 'falhou'::text, 'interrompida'::text, 'parada'::text])) " \
                     '= (finalizada_em IS NOT NULL)'.freeze
  FINALIZADA = "((estado)::text = ANY (ARRAY['concluida'::text, 'falhou'::text, 'interrompida'::text, 'parada'::text, " \
               "'do_antigo'::text])) = (finalizada_em IS NOT NULL)".freeze

  def up
    criar_conversoes
    trocar_check(FINALIZADA)
  end

  # Recusa antes de qualquer DDL: com execução `do_antigo`, o CHECK antigo barraria o motor antigo ainda no ar.
  def down
    if select_value("SELECT 1 FROM autonomia_automacao_execucoes WHERE estado = 'do_antigo' LIMIT 1")
      raise ActiveRecord::IrreversibleMigration, 'há execuções do_antigo: desfazer a F9.2 antes'
    end

    trocar_check(FINALIZADA_ANTES)
    drop_table :autonomia_automacao_conversoes, if_exists: true
  end

  private

  def criar_conversoes
    create_table :autonomia_automacao_conversoes, if_not_exists: true do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.string :antigo_tipo, null: false
      t.bigint :antigo_id, null: false
      t.references :definicao, null: false, foreign_key: { to_table: :autonomia_automacoes }, index: true
      t.jsonb :estado_antes, null: false
      t.timestamps
      t.index %i[account_id antigo_tipo antigo_id], unique: true, name: 'idx_autonomia_automacao_conversoes_antiga'
    end
  end

  # Troca o CHECK sem segurar a tabela: tira o velho, põe o novo NOT VALID e valida.
  def trocar_check(expressao)
    remove_check_constraint :autonomia_automacao_execucoes, name: CHECK, if_exists: true
    add_check_constraint :autonomia_automacao_execucoes, expressao, name: CHECK, validate: false
    validate_check_constraint :autonomia_automacao_execucoes, name: CHECK
  end
end
