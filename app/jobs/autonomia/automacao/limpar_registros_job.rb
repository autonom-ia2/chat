# Apaga, em lotes, os registros da Automação livre com mais de Autonomia::Automacao::Registro::RETENCAO (#2414,
# F2 #2452) e as execuções finalizadas há mais de Autonomia::Automacao::Execucao::RETENCAO que já não têm registro
# (F3 #2459; a chave estrangeira do registro segura a execução). Agendado no config/schedule.yml, uma vez por dia.
class Autonomia::Automacao::LimparRegistrosJob < ApplicationJob
  queue_as :scheduled_jobs

  LOTE = 1000

  def perform
    ::Autonomia::Automacao::Registro.where(created_at: ...::Autonomia::Automacao::Registro::RETENCAO.ago).in_batches(of: LOTE).delete_all
    finalizadas_sem_registro.in_batches(of: LOTE).delete_all
    # G55: a conta da campanha da vez (a rede de segurança fecha cada uma em horas).
    ::Autonomia::Automacao::CampanhaDaVez.where(created_at: ...::Autonomia::Automacao::Registro::RETENCAO.ago).in_batches(of: LOTE).delete_all
  end

  private

  def finalizadas_sem_registro
    ::Autonomia::Automacao::Execucao.where(finalizada_em: ...::Autonomia::Automacao::Execucao::RETENCAO.ago)
                                    .where('NOT EXISTS (SELECT 1 FROM autonomia_automacao_registros registro ' \
                                           'WHERE registro.execucao_id = autonomia_automacao_execucoes.id)')
  end
end
