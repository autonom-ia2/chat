# Image rule for an imported design (#1099), whose images are still at their original address until the import copies
# them: absolute http(s) or raster data: addresses pass, installation paths follow LocalImage, anything else is a problem.
module EmailCampaigns::QualityGate::RemoteImage
  RASTER = %w[data:image/png data:image/jpeg data:image/jpg data:image/gif data:image/webp].freeze

  module_function

  def problem(src, public_root)
    text = src.to_s.strip
    return EmailCampaigns::QualityGate::LocalImage.problem(text, public_root) if text.start_with?('/') && !text.start_with?('//')
    return if text.downcase.start_with?(*RASTER)

    'not an absolute http(s) URL' unless web?(text)
  end

  def web?(text)
    uri = URI.parse(text)
    %w[http https].include?(uri.scheme) && uri.host.present?
  rescue URI::InvalidURIError
    false
  end
end
