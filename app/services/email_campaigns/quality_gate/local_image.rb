# An image is "local" when its src is a root-relative path to a file under public/ (served by the installation
# itself, made absolute at publish time) of at most MAX_BYTES. Returns the problem, or nil when the image is fine.
module EmailCampaigns::QualityGate::LocalImage
  MAX_BYTES = 200 * 1024

  module_function

  def problem(src, public_root)
    uri = URI.parse(src)
    return 'not served by the installation' if uri.scheme || uri.host || !uri.path.start_with?('/')

    file_problem(public_root.join(uri.path.delete_prefix('/')).cleanpath, public_root)
  rescue URI::InvalidURIError
    'invalid URL'
  end

  def file_problem(file, public_root)
    return 'outside public/' unless file.to_s.start_with?("#{public_root}/")
    return 'missing file' unless file.file?

    "#{file.size} bytes > #{MAX_BYTES}" if file.size > MAX_BYTES
  end
end
