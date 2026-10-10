# Public URL of an ActiveStorage blob for use inside an e-mail (<mj-image src>): the recipient's mail client
# fetches it, so the host comes from FRONTEND_URL — jobs have no request to borrow one from. No fallback to
# a fixed domain: without FRONTEND_URL it raises and the caller fails clearly.
module EmailCampaigns::PublicBlobUrl
  module_function

  def call(blob)
    base = ENV['FRONTEND_URL'].presence
    raise 'frontend_url_not_configured' if base.blank?

    uri = URI.parse(base)
    Rails.application.routes.url_helpers.rails_blob_url(blob, host: uri.host, protocol: uri.scheme, port: uri.port)
  end
end
