# A varredura da Automação livre, a cada minuto (#2414 F3, ADR-001 2.4 passo 4). Agendada no config/schedule.yml.
#
# 1. Fecha como "interrompida" a execução que está andando há mais de TRAVADA: a rodada quebrou no meio, e repeti-la
#    faria de novo o que ela já fez. Nunca é repetida.
# 2. Fecha como "interrompida" a execução aberta cujo alvo foi apagado (alvo sumiu).
# 3. Acorda quem espera com o prazo vencido: reserva em lote, de forma atômica (FOR UPDATE SKIP LOCKED, então duas
#    varreduras ao mesmo tempo não pegam a mesma), e enfileira uma rodada para cada uma. A espera mora no banco: um
#    deploy no meio não perde ninguém (F3.3).
#
# As contas sem o motor também passam por aqui: o executor fecha a execução delas como parada (rollback da flag).
class Autonomia::Automacao::VarreduraJob < ApplicationJob
  queue_as :scheduled_jobs

  LOTE = 500
  TRAVADA = 15.minutes

  def perform
    interromper(travadas, 'travada')
    interromper(orfas, 'alvo_sumiu')
    agora = Time.current.floor(6)
    acordar(agora).each { |id| ::Autonomia::Automacao::AvancarJob.perform_later(id, agora.iso8601(6)) }
  end

  private

  def execucoes = ::Autonomia::Automacao::Execucao

  def travadas
    execucoes.where(estado: 'andando', travada_em: ...TRAVADA.ago).limit(LOTE)
  end

  def orfas
    execucoes.abertas.distinct.pluck(:alvo_type).flat_map do |tipo|
      tabela = tipo.constantize.table_name
      execucoes.abertas.where(alvo_type: tipo)
               .where("NOT EXISTS (SELECT 1 FROM #{tabela} alvo WHERE alvo.id = autonomia_automacao_execucoes.alvo_id)")
               .limit(LOTE).to_a
    end
  end

  def interromper(lista, motivo)
    lista.each do |execucao|
      ::Autonomia::Automacao::Registro.create!(account_id: execucao.account_id, automacao_id: execucao.automacao_id, execucao: execucao,
                                               passo: execucao.cursor || 'inicio', resultado: 'falhou', motivo: motivo)
      # Sem validar: a órfã não tem mais alvo, e o `belongs_to` recusaria fechá-la. Só o estado muda aqui.
      execucao.assign_attributes(estado: 'interrompida', travada_em: nil)
      execucao.save!(validate: false)
    end
  end

  # Os ids reservados agora, com `agora` como marca (microssegundos, como o banco guarda).
  def acordar(agora)
    sql = execucoes.sanitize_sql_array([<<~SQL.squish, { agora: agora, lote: LOTE }])
      UPDATE autonomia_automacao_execucoes SET estado = 'andando', travada_em = :agora, updated_at = :agora
      WHERE id IN (SELECT id FROM autonomia_automacao_execucoes
                   WHERE estado = 'esperando' AND finalizada_em IS NULL AND due_at <= :agora
                   ORDER BY due_at LIMIT :lote FOR UPDATE SKIP LOCKED)
      RETURNING id
    SQL
    execucoes.connection.select_values(sql)
  end
end
