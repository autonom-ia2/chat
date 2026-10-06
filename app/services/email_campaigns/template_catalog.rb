# Shared gallery library (#1082): 13 pt-BR designs in db/seeds/email_templates (catalog.json). Sources keep their
# images root-relative (/email-templates/... under public/), so the repository never names a domain; publishing
# points them at the installation that seeds them (FRONTEND_URL), because e-mail clients need absolute URLs.
class EmailCampaigns::TemplateCatalog
  ROOT = Rails.root.join('db/seeds/email_templates').freeze

  def self.entries
    @entries ||= JSON.parse(ROOT.join('catalog.json').read).freeze
  end

  # Global templates of earlier libraries, removed by the seed (account templates are never touched).
  def self.retired_names
    @retired_names ||= JSON.parse(ROOT.join('retired.json').read).fetch('names').freeze
  end

  def self.key_for(template)
    return if template.account_id

    entries.find { |entry| entry.fetch('name') == template.name }&.fetch('key')
  end

  # Sanitized MJML exactly as the editor stores it, images still root-relative.
  def self.body(entry)
    EmailCampaigns::Ai::Sanitizer.new(ROOT.join(entry.fetch('path')).read).perform
  end

  def self.html_path(entry)
    ROOT.join(entry.fetch('path')).sub_ext('.html')
  end

  # Strict mjml-browser compilation of #body, in the line format the versioned .html files use. Build time only.
  def self.compile(entry)
    result = EmailCampaigns::MjmlCompiler.call(body(entry))
    html = result.html.present? ? "#{result.html.lines.map(&:rstrip).join("\n")}\n" : ''
    EmailCampaigns::MjmlCompiler::Result.new(html, result.errors)
  end

  # [mjml, html] ready for the database, with images served by the installation at base_url.
  def self.published(entry, base_url:)
    base = installation_uri(base_url)
    [body(entry), html_path(entry).read].map { |markup| absolutize_images(markup, base) }
  end

  def self.installation_uri(base_url)
    uri = URI.parse(base_url.to_s)
    raise ArgumentError, 'FRONTEND_URL must be an absolute http(s) URL' unless %w[http https].include?(uri.scheme) && uri.host.present?

    uri
  rescue URI::InvalidURIError
    raise ArgumentError, 'FRONTEND_URL must be an absolute http(s) URL'
  end

  # Root-relative src values found by the HTML parser are replaced literally (src="..."), so nothing else in the
  # markup is re-serialized.
  def self.absolutize_images(markup, base)
    sources = Nokogiri::HTML5.fragment(markup).css('[src]').filter_map { |node| node['src'] }.uniq
    sources.select { |src| root_relative?(src) }.reduce(markup) do |out, src|
      out.gsub(%(src="#{src}"), %(src="#{URI.join(base, src)}"))
    end
  end

  def self.root_relative?(src)
    uri = URI.parse(src)
    uri.scheme.nil? && uri.host.nil? && src.start_with?('/') && !src.start_with?('//')
  rescue URI::InvalidURIError
    false
  end

  private_class_method :installation_uri, :absolutize_images, :root_relative?
end
