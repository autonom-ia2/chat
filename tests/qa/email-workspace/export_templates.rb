# Read-only fixture export for the local browser harness. No database writes.
output = Rails.root.join('.codex/800/models')
FileUtils.mkdir_p(output)
EmailCampaigns::TemplateCatalog.entries.each do |entry|
  key = entry.fetch('key')
  output.join("#{key}.mjml").write(EmailCampaigns::TemplateCatalog.body(entry))
  output.join("#{key}.html").write(EmailCampaigns::TemplateCatalog::ROOT.join(entry.fetch('path')).sub_ext('.html').read)
end
puts "Exported #{EmailCampaigns::TemplateCatalog.entries.length} sanitized local designs."
