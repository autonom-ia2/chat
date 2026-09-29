require 'tmpdir'

class Relationships::CompanyPreviewJob < ApplicationJob
  queue_as :low
  MAX_BYTES = 25.megabytes
  LOCK_ID = 757_005
  DEMAND_TTL = 10.minutes
  CAPACITY_DELAY = 10.seconds
  MAX_FAILURES = 3
  RETRY_DELAY = 10.seconds

  def self.ready?(attachment)
    attachment.relationship_preview.attached? &&
      attachment.meta&.dig('relationship_preview', 'ready_blob_id') == attachment.file.blob_id
  end

  def self.request(attachment)
    attachment.with_lock do
      blob = attachment.file.blob
      return 'unavailable' unless Relationships::PreviewRenderer.supported?(blob.content_type) && blob.byte_size <= MAX_BYTES
      return 'ready' if ready?(attachment)

      enqueue_preview(attachment, blob)
    end
  end

  def self.enqueue_preview(attachment, blob, force: false)
    preview = attachment.meta.to_h.fetch('relationship_preview', {})
    same_blob = preview['blob_id'] == blob.id
    age = Time.current.to_i - preview['requested_at'].to_i
    permanent = preview['failure'] == 'content'
    return preview['status'] if !force && same_blob && (permanent || age < DEMAND_TTL)

    metadata = { 'status' => 'pending', 'blob_id' => blob.id, 'requested_at' => Time.current.to_i, 'failure_count' => 0 }
    attachment.update!(meta: (attachment.meta || {}).merge('relationship_preview' => metadata))
    perform_later(attachment.id, blob.id)
    'pending'
  end

  def perform(id, blob_id)
    attachment = Attachment.find_by(id: id)
    return unless attachment
    unless preview_features_enabled?(attachment)
      clear_pending_request(attachment, blob_id)
      return
    end
    return unless eligible?(attachment, blob_id)

    with_processing_slot(attachment, blob_id) do
      attachment.reload
      if preview_features_enabled?(attachment)
        generate(attachment, blob_id) if eligible?(attachment, blob_id)
      else
        clear_pending_request(attachment, blob_id)
      end
    end
  rescue StandardError => e
    Rails.logger.info("Relationship preview retry attachment=#{id} error=#{e.class.name}")
    retry_transient(attachment, blob_id) if attachment&.persisted?
  end

  private

  def eligible?(attachment, blob_id)
    return false unless attachment
    return false unless attachment.file.blob_id == blob_id
    return false if self.class.ready?(attachment)
    return false unless retry_due?(attachment)

    preview_features_enabled?(attachment)
  end

  def preview_features_enabled?(attachment)
    attachment.account.feature_enabled?('companies') && attachment.account.feature_enabled?('relationships_company_media')
  end

  def clear_pending_request(attachment, blob_id)
    attachment.with_lock do
      next unless attachment.file.blob_id == blob_id

      preview = attachment.meta.to_h.fetch('relationship_preview', {})
      next unless preview['status'] == 'pending' && preview['blob_id'] == blob_id

      attachment.update!(meta: attachment.meta.to_h.except('relationship_preview'))
    end
  end

  def retry_due?(attachment)
    preview = attachment.meta.to_h.fetch('relationship_preview', {})
    preview['status'] != 'unavailable' && preview['retry_at'].to_i <= Time.current.to_i
  end

  def with_processing_slot(attachment, blob_id)
    Attachment.connection_pool.with_connection do |connection|
      unless connection.select_value("SELECT pg_try_advisory_lock(#{LOCK_ID})")
        # Capacity is not a content failure. Expired demand can be requested again.
        requested_at = attachment.meta&.dig('relationship_preview', 'requested_at').to_i
        self.class.set(wait: CAPACITY_DELAY).perform_later(attachment.id, blob_id) if requested_at > DEMAND_TTL.ago.to_i
        next
      end
      begin
        yield
      ensure
        connection.execute("SELECT pg_advisory_unlock(#{LOCK_ID})")
      end
    end
  end

  def mark_unavailable(attachment, blob_id)
    attachment.with_lock do
      next unless attachment.file.blob_id == blob_id

      metadata = attachment.meta || {}
      preview = (metadata['relationship_preview'] || {}).merge('status' => 'unavailable', 'failure' => 'content', 'blob_id' => blob_id)
      attachment.update!(meta: metadata.merge('relationship_preview' => preview))
    end
  end

  def retry_transient(attachment, blob_id)
    attachment.with_lock do
      next unless attachment.file.blob_id == blob_id
      next if self.class.ready?(attachment)

      preview = attachment.meta.fetch('relationship_preview')
      count = preview['failure_count'].to_i + 1
      exhausted = count >= MAX_FAILURES
      delay = RETRY_DELAY * (2**(count - 1))
      preview = preview.merge('status' => exhausted ? 'unavailable' : 'pending', 'failure' => 'transient',
                              'failure_count' => count, 'retry_at' => (Time.current + delay).to_i)
      attachment.update!(meta: attachment.meta.merge('relationship_preview' => preview))
      self.class.set(wait: delay).perform_later(attachment.id, blob_id) unless exhausted
    end
  end

  def generate(attachment, blob_id)
    blob = attachment.file.blob
    return mark_unavailable(attachment, blob_id) if blob.byte_size > MAX_BYTES

    Dir.mktmpdir('relationship-preview') do |directory|
      blob.open(tmpdir: directory) do |input|
        output = File.join(directory, 'preview.jpg')
        success = Relationships::PreviewRenderer.new.render(blob.content_type, input.path, output)
        return mark_unavailable(attachment, blob_id) unless success

        persist_preview(attachment, blob_id, output)
      end
    end
  end

  def persist_preview(attachment, blob_id, output)
    # Upload before publishing ready: attach(io:) defers upload until after commit,
    # when the file may already be closed and a storage failure cannot roll back status.
    preview_blob = nil
    File.open(output) do |file|
      # Keep the persisted reference before upload so a partial storage failure can be purged.
      preview_blob = ActiveStorage::Blob.create_after_unfurling!(io: file, filename: 'preview.jpg', content_type: 'image/jpeg')
      preview_blob.upload_without_unfurling(file)
    end
    attachment.with_lock do
      next unless eligible?(attachment, blob_id)

      attachment.relationship_preview.attach(preview_blob)
      metadata = attachment.meta.fetch('relationship_preview')
      attachment.update!(meta: attachment.meta.merge('relationship_preview' => metadata.merge('status' => 'ready', 'ready_blob_id' => blob_id)))
    end
  ensure
    preview_blob.purge_later if preview_blob && !preview_blob.attachments.exists?
  end
end
