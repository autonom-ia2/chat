# Apaga, em lotes, os registros da Automação livre com mais de Autonomia::Automacao::Registro::RETENCAO (#2414,
# F2 #2452) e as execuções finalizadas há mais de Autonomia::Automacao::Execucao::RETENCAO que já não têm registro
# (F3 #2459; a chave estrangeira do registro segura a execução). Agendado no config/schedule.yml, uma vez por dia.
#
# O registro da execução ainda aberta fica (#2750): a espera longa (o "esperar até" sem prazo guarda nele o começo da
# espera) não perde o histórico nem o começo no meio do caminho. Sai depois que ela terminar.
#
# A campanha da vez (G55) tem prazo próprio, contado de quando fechou, e nunca sai com execução da vez aberta.
class Autonomia::Automacao::LimparRegistrosJob < ApplicationJob
  queue_as :scheduled_jobs

  LOTE = 1000

  def perform
    ::Autonomia::Automacao::Registro.where(created_at: ...::Autonomia::Automacao::Registro::RETENCAO.ago)
                                    .where.not(execucao_id: ::Autonomia::Automacao::Execucao.abertas.select(:id))
                                    .in_batches(of: LOTE).delete_all
    finalizadas_sem_registro.in_batches(of: LOTE).delete_all
    vezes_encerradas.in_batches(of: LOTE).delete_all
  end

  private

  # G55: a linha da campanha da vez é o que impede a mesma vez de mandar de novo (sem ela, a próxima chegada abriria a vez
  # outra vez e a campanha sairia de novo a quem já recebeu). Só sai a vez fechada há mais de CampanhaDaVez::RETENCAO e
  # sem execução aberta (a que espera ainda pode chegar ao passo). A vez aberta nunca sai: a rede de segurança a fecha.
  def vezes_encerradas
    ::Autonomia::Automacao::CampanhaDaVez.where(fechada_em: ...::Autonomia::Automacao::CampanhaDaVez::RETENCAO.ago)
                                         .where.not(id: ::Autonomia::Automacao::CampanhaDaVez.com_execucao_aberta.select(:id))
  end

  def finalizadas_sem_registro
    ::Autonomia::Automacao::Execucao.where(finalizada_em: ...::Autonomia::Automacao::Execucao::RETENCAO.ago)
                                    .where('NOT EXISTS (SELECT 1 FROM autonomia_automacao_registros registro ' \
                                           'WHERE registro.execucao_id = autonomia_automacao_execucoes.id)')
  end
end
