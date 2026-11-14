# #2921: puts back in the queue the import of contacts, of an audience or of a campaign base that lost its job, so it
# ends by itself. Registered in config/schedule.yml. Two cases, both measured against
# CampaignImports::Config.stalled_import_after:
#
# - `importing` with no move for that long: the worker died (killed, deploy in the middle of the writing). The last
#   move is the newest of the import's own `updated_at`, which the Importer touches when it starts and after each
#   block, and of its rows' `updated_at`. An import that moved within the stall time is never touched.
# - `queued` for that long: "confirmar" (or this sweep) committed `queued` and the job never reached the queue.
#
# Each import is checked again under its lock, the same lock the Importer takes to start, and gets a new `queued_at`
# there: two sweeps never put the same import in the queue twice, and an import still waiting is not put again every
# run. A repeated job is harmless: the Importer leaves when it finds the import `importing` or completed, and skips
# the rows already imported.
#
# The imports the automation step "para cada item" writes are left out: they have no file to read again, and the
# step closes them itself (Autonomia::Automacao::ImportacaoDoParaCada).
class CampaignImports::StalledImportsJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    return unless CampaignImports::Config.enabled?

    lost_imports.find_each do |campaign_import|
      requeue(campaign_import)
    rescue StandardError => e
      # One import that breaks does not stop the others. No message: it may carry what the import holds.
      Rails.logger.error("[CampaignImports::StalledImportsJob] import_id=#{campaign_import.id} #{e.class}")
    end
    ContactImports::Trazer::ConferenciasParadas.new.call
  end

  private

  def lost_imports
    file_imports = CampaignImport.where("COALESCE(options->>'origem', '') <> ?", CampaignImport::AUTOMATION_ORIGIN)
    file_imports.importing.where(updated_at: ...stall_limit).or(file_imports.queued.where(queued_at: ...stall_limit))
  end

  def stall_limit
    CampaignImports::Config.stalled_import_after.ago
  end

  def lost?(campaign_import)
    return campaign_import.queued_at < stall_limit if campaign_import.queued?

    campaign_import.importing? && last_move(campaign_import) < stall_limit
  end

  def last_move(campaign_import)
    [campaign_import.updated_at, campaign_import.campaign_import_rows.maximum(:updated_at)].compact.max
  end

  def requeue(campaign_import)
    requeued = false
    campaign_import.with_lock do
      next unless lost?(campaign_import)

      campaign_import.update!(status: :queued, queued_at: Time.current)
      requeued = true
    end
    return unless requeued

    CampaignImports::ImportJob.perform_later(campaign_import)
    Rails.logger.warn("[CampaignImports::StalledImportsJob] import_id=#{campaign_import.id} requeued")
  end
end
