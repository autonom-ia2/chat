# Retenção do consultor de anúncios da Meta (#1110, F5), todo dia às 5h30 de Brasília, depois da leitura das 4h:
# - análises (runs) com mais de RUNS_TTL: o texto e os fatos de cada dia só servem enquanto o dia é recente;
# - ações com mais de ACTIONS_TTL: a métrica de aceite ("aceita ≥ 4 de 5") precisa de histórico longo;
# - janelas de frequência com mais de FREQUENCY_TTL: o consultor só lê a mais recente.
#
# Apaga em lotes de BATCH, para não segurar a tabela inteira numa transação só. Apagar um run deixa
# `run_id`/`last_run_id` das ações nulos (a chave estrangeira é `on_delete: :nullify`).
class Crm::MetaAds::Advisor::PruneJob < ApplicationJob
  queue_as :low

  RUNS_TTL = 90.days
  ACTIONS_TTL = 400.days
  FREQUENCY_TTL = 35.days
  BATCH = 1_000

  def perform
    today = Time.zone.today
    prune(Crm::MetaAdvisorRun.where(local_date: ...(today - RUNS_TTL)))
    prune(Crm::MetaAdvisorAction.where(local_date: ...(today - ACTIONS_TTL)))
    prune(Crm::MetaAdFrequencyWindow.where(date_end: ...(today - FREQUENCY_TTL)))
  end

  private

  def prune(scope)
    scope.in_batches(of: BATCH).delete_all
  end
end
