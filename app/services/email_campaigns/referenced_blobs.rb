# The ActiveStorage blobs an e-mail body shows (#1822).
#
# The builder upload, the AI, the template import and the brand kit put images in the body as
# `/rails/active_storage/blobs/redirect/<signed_id>/<filename>` URLs, each blob attached to whoever
# uploaded it. A campaign or template that only copies the URL loses the image when that owner is
# destroyed (draft deleted, import expired, logo replaced). Callers attach these blobs to themselves:
# ActiveStorage never purges a blob that is still attached to another record.
#
# Only images already attached to an e-mail record of the same account count (by attachment name, so an
# import's original file never does); a pasted URL from another account is ignored. Plain string
# scanning, no regex.
class EmailCampaigns::ReferencedBlobs
  BLOBS_PATH = '/rails/active_storage/blobs/'.freeze
  ROUTE_PREFIXES = %w[redirect/ proxy/].freeze
  IMAGE_ATTACHMENTS = {
    'EmailCampaign' => 'builder_assets',
    'EmailCampaignTemplate' => 'builder_assets',
    'EmailCampaignTemplateImport' => 'images',
    'BrandKit' => 'logo'
  }.freeze

  def initialize(account, *bodies)
    @account = account
    @bodies = bodies.compact.map(&:to_s)
  end

  def blob_ids
    ids = signed_ids.filter_map { |signed_id| ActiveStorage::Blob.find_signed(signed_id)&.id }.uniq
    return [] if ids.empty?

    owned_blob_ids(ids)
  end

  private

  def signed_ids
    @bodies.flat_map { |body| body.split(BLOBS_PATH).drop(1) }.filter_map { |tail| signed_id_in(tail) }.uniq
  end

  def signed_id_in(tail)
    prefix = ROUTE_PREFIXES.find { |route| tail.start_with?(route) }
    path = prefix ? tail.delete_prefix(prefix) : tail
    path.split('/', 2).first.presence
  end

  def owned_blob_ids(ids)
    IMAGE_ATTACHMENTS.flat_map do |type, name|
      owners = type.constantize.where(account_id: @account.id).select(:id)
      ActiveStorage::Attachment.where(blob_id: ids, record_type: type, name: name, record_id: owners).pluck(:blob_id)
    end.uniq
  end
end
