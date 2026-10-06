# Primeira carga de 90 dias de uma conexão (#1073). Ver Crm::MetaAds::Insights::Backfill.
#
# Sem `sleep`: cada execução dá um passo e se reagenda. Pede o relatório por anúncio, confere a cada POLL_WAIT
# até ficar pronto (no máximo MAX_POLLS vezes), lê, marca a carga como feita e repete com o relatório por
# posicionamento. Falhou no meio: solta a marca, e a rodada diária das 4h tenta de novo enquanto a carga por
# anúncio não tiver terminado.
class Crm::MetaAds::InsightsBackfillJob < ApplicationJob
  queue_as :low

  POLL_WAIT = 30.seconds
  MAX_POLLS = 120

  # Enfileira a carga se nenhuma estiver rodando para esta conexão.
  def self.start(connection)
    return false unless Crm::MetaAds::Insights::Backfill.claim(connection.id)

    perform_later(connection.id)
    true
  end

  def perform(connection_id, kind = 'ads', report_run_id = nil, polls = 0)
    connection = Crm::MetaAdsConnection.find_by(id: connection_id)
    backfill = connection && Crm::MetaAds::Insights::Backfill.new(connection, kind)
    return finish(connection_id) unless backfill&.readable?
    return request(backfill, connection_id, kind) if report_run_id.nil?

    case backfill.status(report_run_id)
    when :running then wait(connection_id, kind, report_run_id, polls)
    when :completed then complete(connection, backfill, kind, report_run_id)
    else finish(connection_id)
    end
  end

  private

  def request(backfill, connection_id, kind)
    report_run_id = backfill.start
    return finish(connection_id) if report_run_id.nil?

    self.class.set(wait: POLL_WAIT).perform_later(connection_id, kind, report_run_id, 0)
  end

  def wait(connection_id, kind, report_run_id, polls)
    return finish(connection_id) if polls >= MAX_POLLS

    self.class.set(wait: POLL_WAIT).perform_later(connection_id, kind, report_run_id, polls + 1)
  end

  def complete(connection, backfill, kind, report_run_id)
    return finish(connection.id) unless backfill.read!(report_run_id)
    return finish(connection.id) unless kind == 'ads'

    connection.update!(insights_backfilled_at: Time.current)
    self.class.perform_later(connection.id, 'placements')
  end

  def finish(connection_id)
    Crm::MetaAds::Insights::Backfill.release(connection_id)
  end
end
