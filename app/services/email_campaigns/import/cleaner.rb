# The cleaning chain of an imported model (#1099), the same for a whole HTML page and for the HTML inside an MJML
# block: Outlook branches out, allowlist sanitizing, merge tags, hidden text and pixels, links and images. Returns the
# node whose content the converter reads (the body, for a page). The preview of the original (OriginalPreview) skips
# the merge tags (tags: false): it shows the fields as the person wrote them, so the screen can say what became what.
class EmailCampaigns::Import::Cleaner
  def self.call(root, report, base_url: nil, tags: true)
    EmailCampaigns::Import::Outlook.call(root, report)
    EmailCampaigns::Import::Sanitizer.call(root, report)
    target = root.at_css('body') || root
    EmailCampaigns::Import::MergeTags.new(report).apply(target) if tags
    EmailCampaigns::Import::Visibility.call(target, report)
    EmailCampaigns::Import::LinkPolicy.new(report, base_url: base_url).call(target)
  end
end
