# A varredura da Automação livre, a cada minuto (#2414 F3, ADR-001 2.4 passo 4). Agendada no config/schedule.yml.
#
# 1. Acorda quem espera com o prazo vencido e reenfileira quem foi reservado há mais de TRAVADA sem começar (fila
#    atrasada, Redis fora na hora de enfileirar), seja qual for o prazo: a reserva da escuta guarda no `due_at` o
#    prazo do "esperar até", que pode estar dias à frente: reserva em lote, de forma atômica (FOR UPDATE SKIP LOCKED, então
#    duas varreduras ao mesmo tempo não pegam a mesma), com uma marca nova, e enfileira uma rodada para cada uma. O
#    job velho, se ainda vier, chega com a marca antiga e não anda. A espera mora no banco: um deploy no meio não
#    perde ninguém (F3.3). Vem primeiro: um erro nos passos de baixo não para as esperas.
# 2. Fecha como "interrompida" a execução que começou e está andando há mais de TRAVADA: a rodada quebrou no meio, e
#    repeti-la faria de novo o que ela já fez. Nunca é repetida. Começou = `due_at` vazio (ver Executor).
# 3. Fecha como "interrompida" a aberta cujo alvo foi apagado (alvo sumiu), entre as de `due_at` já vencido, em lote,
#    pelo índice parcial do `due_at` (#2750, revisão): a que ainda não venceu fecha quando vencer (aqui, ou na rodada,
#    pelo Executor#impedimento). A espera sem prazo vence uma vez por dia (EsperaNoExecutor::CONFERENCIA).
# 4. A cobertura da agente de IA (decisão 18) da execução fechada aqui, ou da conta que desligou o Motor, devolve a
#    conversa à pessoa tirada (Cobertura): a IA não fica presa.
#
# Cada linha que falha vai para o log e não para as outras. As contas sem o motor também passam por aqui: o executor
# fecha a execução delas como parada (rollback da flag).
class Autonomia::Automacao::VarreduraJob < ApplicationJob
  queue_as :scheduled_jobs

  LOTE = 500
  TRAVADA = 15.minutes

  def perform
    agora = Time.current.floor(6)
    acordar(agora).each { |id| enfileirar(id, agora) }
    interromper(travadas(agora), 'travada')
    interromper(orfas(agora), 'alvo_sumiu')
    coberturas_sem_motor
  end

  private

  def execucoes = ::Autonomia::Automacao::Execucao

  # Os ids reservados agora, com `agora` como marca (microssegundos, como o banco guarda).
  def acordar(agora)
    sql = execucoes.sanitize_sql_array([<<~SQL.squish, { agora: agora, limite: agora - TRAVADA, lote: LOTE }])
      UPDATE autonomia_automacao_execucoes SET estado = 'andando', travada_em = :agora, updated_at = :agora
      WHERE id IN (SELECT id FROM autonomia_automacao_execucoes
                   WHERE finalizada_em IS NULL AND due_at IS NOT NULL
                     AND ((estado = 'esperando' AND due_at <= :agora) OR (estado = 'andando' AND travada_em < :limite))
                   ORDER BY due_at LIMIT :lote FOR UPDATE SKIP LOCKED)
      RETURNING id
    SQL
    execucoes.connection.select_values(sql)
  end

  def enfileirar(id, agora)
    ::Autonomia::Automacao::AvancarJob.perform_later(id, agora.iso8601(6))
  rescue StandardError => e
    # A reserva fica; daqui a TRAVADA a varredura a reenfileira.
    Rails.logger.error("[automacao][varredura] não enfileirou execucao=#{id} #{e.class}: #{e.message}")
  end

  def travadas(agora)
    execucoes.where(estado: 'andando', due_at: nil, travada_em: ...(agora - TRAVADA)).limit(LOTE)
  end

  def orfas(agora)
    vencidas = execucoes.abertas.where(due_at: ..agora)
    vencidas.distinct.pluck(:alvo_type).flat_map do |tipo|
      tabela = tipo.constantize.table_name
      vencidas.where(alvo_type: tipo)
              .where("NOT EXISTS (SELECT 1 FROM #{tabela} alvo WHERE alvo.id = autonomia_automacao_execucoes.alvo_id)")
              .limit(LOTE).to_a
    rescue NameError => e
      Rails.logger.error("[automacao][varredura] alvo_type desconhecido #{tipo}: #{e.message}")
      []
    end
  end

  def interromper(lista, motivo)
    lista.each do |execucao|
      next unless fechar(execucao)

      ::Autonomia::Automacao::Registro.create!(account_id: execucao.account_id, automacao_id: execucao.automacao_id, execucao: execucao,
                                               passo: execucao.cursor || 'inicio', resultado: 'falhou', motivo: motivo)
      ::Autonomia::Automacao::Cobertura.encerrar([execucao.id])
      # G55: a execução fechada deixa de segurar a campanha da vez.
      ::Autonomia::Automacao::CampanhaDaOcorrencia.conferir_execucao(execucao)
    rescue StandardError => e
      Rails.logger.error("[automacao][varredura] não fechou execucao=#{execucao.id} motivo=#{motivo} #{e.class}: #{e.message}")
    end
  end

  def coberturas_sem_motor
    ::Autonomia::Automacao::Cobertura.encerrar_sem_motor
  rescue StandardError => e
    Rails.logger.error("[automacao][varredura] não encerrou as coberturas sem motor #{e.class}: #{e.message}")
  end

  # Só fecha se ela continua como foi lida: a rodada que terminou nesse meio-tempo vence. Sem callback (a órfã não
  # passa no `belongs_to`), com a finalizada_em junto, como o CHECK pede, e sem os textos da IA (Execucao::AO_TERMINAR).
  def fechar(execucao)
    agora = Time.current
    execucoes.where(id: execucao.id, estado: execucao.estado, travada_em: execucao.travada_em)
             .update_all(estado: 'interrompida', travada_em: nil, finalizada_em: agora, updated_at: agora, # rubocop:disable Rails/SkipsModelValidations
                         **::Autonomia::Automacao::Execucao::AO_TERMINAR) == 1
  end
end
