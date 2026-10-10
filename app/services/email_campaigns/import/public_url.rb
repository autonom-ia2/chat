# The address an imported image is served at (#1099, delivery B): the same one the e-mail builder and the AI already
# put in campaigns — the ActiveStorage redirect of the blob, on the installation's FRONTEND_URL. Its signed id carries no
# expiry (ActiveStorage.urls_expire_in is not set), so the address keeps working in an inbox weeks later, without any
# session. `owned_blob` reads such an address back and returns the blob only when it belongs to the given import.
module EmailCampaigns::Import::PublicUrl
  BLOB_SEGMENTS = %w[rails active_storage blobs].freeze
  ROUTES = %w[redirect proxy].freeze

  module_function

  def for(blob)
    base = frontend
    Rails.application.routes.url_helpers.rails_blob_url(blob, host: base.host, protocol: base.scheme, port: base.port)
  end

  def owned_blob(url, import)
    blob = blob_for(url)
    blob if blob && import.images_attachments.exists?(blob_id: blob.id)
  end

  def blob_for(url)
    uri = URI.parse(url.to_s.strip)
    return unless same_origin?(uri)

    segments = uri.path.to_s.split('/').reject(&:empty?)
    return unless segments.first(3) == BLOB_SEGMENTS && ROUTES.include?(segments[3])

    ActiveStorage::Blob.find_signed(segments[4])
  rescue URI::InvalidURIError
    nil
  end

  def same_origin?(uri)
    base = frontend
    uri.scheme == base.scheme && uri.host == base.host && uri.port == base.port
  end

  def frontend
    value = ENV.fetch('FRONTEND_URL', nil).to_s.strip
    uri = URI.parse(value)
    raise EmailCampaigns::Import::Error, :configuration unless %w[http https].include?(uri.scheme) && uri.host.present?

    uri
  rescue URI::InvalidURIError
    raise EmailCampaigns::Import::Error, :configuration
  end
end
