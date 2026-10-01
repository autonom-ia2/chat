require 'open3'

namespace :email_campaign_templates do
  desc 'Compile sanitized shared templates before publishing their HTML assets (requires frontend dependencies)'
  task compile: :environment do
    compiler = Rails.root.join('lib/tasks/support/mjml_compile.js')
    prepared = EmailCampaigns::TemplateCatalog.entries.map do |entry|
      mjml = EmailCampaigns::TemplateCatalog.body(entry)
      html, error, status = Open3.capture3('node', compiler.to_s, stdin_data: mjml, chdir: Rails.root.to_s)
      raise "Template compilation failed: #{entry.fetch('key')} (#{error.bytesize} diagnostic bytes)" unless status.success? && html.present?

      html = "#{html.lines.map(&:rstrip).join("\n")}\n"
      [EmailCampaigns::TemplateCatalog::ROOT.join(entry.fetch('path')).sub_ext('.html'), html]
    end
    prepared.each { |path, html| path.write(html) }
    puts "Compiled #{prepared.length} shared templates with protected footers."
  end

  desc 'Restore the 14 shared gallery templates without changing account-owned templates'
  task seed: :environment do
    prepared = EmailCampaigns::TemplateCatalog.entries.map do |entry|
      mjml = EmailCampaigns::TemplateCatalog.body(entry)
      html = EmailCampaigns::TemplateCatalog::ROOT.join(entry.fetch('path')).sub_ext('.html').read
      unless html.include?('{{ unsubscribe_url }}') && html.include?('footer-locked')
        raise "Template preview missing protected footer: #{entry.fetch('key')}"
      end

      [entry, mjml, html]
    end
    # Prepare all designs before the bounded write; never publish a partial catalog.
    EmailCampaignTemplate.transaction do
      prepared.each do |entry, mjml, html|
        template = EmailCampaignTemplate.find_or_initialize_by(account_id: nil, name: entry.fetch('name'))
        template.update!(body_mjml: mjml, body_html: html, category: entry.fetch('category'))
      end
    end
    puts "Restored #{prepared.length} shared templates. Account templates preserved."
  end
end
