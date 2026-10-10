# The .zip of a model is read with a base address on a reserved domain, so its images resolve by their relative name
# (ZipReader). A relative link of that page resolves to the same domain and leads nowhere: this step takes those links
# out after the conversion — the href of a block, or the anchor inside a text (its words stay) — and records each one
# as a removed link. Parsed attributes and HTML (Nokogiri); the only string test is a prefix — no regex.
module EmailCampaigns::Import::ArchiveLinks
  TEXT_TAGS = %w[mj-text mj-table].freeze

  module_function

  def call(mjml, report)
    base = EmailCampaigns::Import::ZipReader::BASE_URL
    out = EmailCampaigns::MjmlCanonicalizer.call(mjml) do |root, _cut|
      root.css('[href]').select { |node| node['href'].to_s.start_with?(base) }.each do |node|
        drop(report, node['href'])
        node.remove_attribute('href')
      end
      {}
    end
    EmailCampaigns::MjmlEndingContent.map(out, TEXT_TAGS) { |content| unlink(content, base, report) }
  end

  def unlink(content, base, report)
    return content unless content.include?(base)

    fragment = EmailCampaigns::Import::Limits.fragment(content)
    fragment.css('a[href]').select { |link| link['href'].to_s.start_with?(base) }.each do |link|
      drop(report, link['href'])
      link.replace(link.children)
    end
    fragment.to_html
  end

  def drop(report, href)
    report.add(:link_removed)
    report.drop_link(href, :relative)
  end
end
