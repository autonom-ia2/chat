# Roda a importação da identidade visual de um site (#1076) e guarda a proposta em brand_import_jobs.
# Erro esperado vira error_code estável; erro inesperado vira 'internal_error' sem nova tentativa
# (a pessoa pede de novo pela tela).
class BrandKits::ImportJob < ApplicationJob
  queue_as :low

  def perform(job_id)
    job = BrandImportJob.find_by(id: job_id)
    return unless job&.queued?

    job.update!(status: :running, started_at: Time.current)
    proposal = BrandKits::SiteImporter.new(job.url).perform
    job.update!(status: :succeeded, result: proposal, finished_at: Time.current)
  rescue BrandKits::SiteImporter::Error => e
    job&.fail!(e.code)
  rescue StandardError => e
    Rails.logger.error("[BrandKits::ImportJob] job=#{job_id} #{e.class.name}")
    job&.fail!('internal_error')
  end
end
