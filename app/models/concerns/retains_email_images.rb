# A campaign or template keeps the files its body shows (#1822): every blob the body points at (image,
# and the builder's video or PDF) is attached to it as a builder asset, so deleting the draft, the import
# or the old logo that uploaded it no longer breaks this e-mail. Global gallery templates (no account)
# are left alone. Known limit: a blob whose owner is already gone (purge queued) is not taken over, since
# accepting ownerless blobs would let a pasted URL from another account in.
#
# Only adds, on purpose: letting an attachment go is exactly what breaks an e-mail that still shows it.
# Runs in the save's transaction, so a failure rolls the body back and the next save retries.
module RetainsEmailImages
  extend ActiveSupport::Concern

  included do
    has_many_attached :builder_assets

    after_save :retain_email_images, if: :email_body_changed?
  end

  def retain_email_images(retried: false)
    return if account_id.blank?

    blob_ids = EmailCampaigns::ReferencedBlobs.new(account, body_html, body_mjml).blob_ids
    return if blob_ids.empty?

    # Idempotent under concurrent saves; no per-image touch of this record. The blobs already exist and
    # were checked above, so the attachment has nothing left to validate.
    rows = blob_ids.map do |blob_id|
      { name: 'builder_assets', record_type: self.class.polymorphic_name, record_id: id, blob_id: blob_id, created_at: Time.current }
    end
    # Savepoint: a failed insert must not abort the save's transaction, so the retry below can run.
    self.class.transaction(requires_new: true) do
      ActiveStorage::Attachment.insert_all(rows, unique_by: :index_active_storage_attachments_uniqueness) # rubocop:disable Rails/SkipsModelValidations
    end
  rescue ActiveRecord::InvalidForeignKey
    # A blob purged between the check and the insert: look again once, without the one that is gone.
    raise if retried

    retain_email_images(retried: true)
  end

  private

  def email_body_changed?
    saved_change_to_body_html? || saved_change_to_body_mjml?
  end
end
