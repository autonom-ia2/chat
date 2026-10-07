# The HTML path of a template import (#1099): parse within the limits, read the subject, bring the stylesheet into the
# tags, clean (Cleaner) and convert (Converter). The hidden preview text found on the way becomes the preheader.
class EmailCampaigns::Import::HtmlSource
  def self.call(source, report, base_url: nil)
    new(source, report, base_url).call
  end

  def initialize(source, report, base_url)
    @source = source
    @report = report
    @base_url = base_url
  end

  def call
    doc = EmailCampaigns::Import::Limits.html!(@source)
    title = EmailCampaigns::Import::MergeTags.new(@report).plain_text(doc.at_css('title')&.text.to_s)
    EmailCampaigns::Import::StyleInliner.call(doc, @report)
    body = EmailCampaigns::Import::Cleaner.call(doc.root, @report, base_url: @base_url)
    document = EmailCampaigns::Import::Converter.call(body, @report)
    document.with(title: title.presence, preview: @report.preheader)
  end
end
