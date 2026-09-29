# Real cross-connection lock tests cannot use transactional fixtures. Clean only
# auxiliary records created by these examples; never run their queued callbacks.
RSpec.configure do |config|
  config.around(:each, :relationships_committed_fixtures) do |example|
    configuration_ids = InstallationConfig.ids
    blob_ids = ActiveStorage::Blob.ids
    begin
      example.run
    ensure
      ActiveStorage::Blob.where.not(id: blob_ids).where.missing(:attachments).find_each(&:purge)
      InstallationConfig.where.not(id: configuration_ids).destroy_all
      GlobalConfig.clear_cache
    end
  end
end
