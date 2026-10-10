namespace :email_campaign_templates do
  desc 'Compile the shared library to its versioned HTML and run the quality gate (build time; needs frontend dependencies)'
  task compile: :environment do
    catalog = EmailCampaigns::TemplateCatalog
    prepared = catalog.entries.map do |entry|
      compiled = catalog.compile(entry)
      violations = EmailCampaigns::QualityGate.new(mjml: catalog.body(entry), html: compiled.html,
                                                   compile_errors: compiled.errors).violations
      if violations.any?
        details = violations.map { |violation| "  #{violation.check}: #{violation.detail}" }.join("\n")
        raise "Template #{entry.fetch('key')} failed the quality gate:\n#{details}"
      end

      [catalog.html_path(entry), compiled.html]
    end
    prepared.each { |path, html| path.write(html) }
    puts "Compiled #{prepared.length} shared templates; quality gate passed."
  end

  desc 'Publish the shared library (global templates only). Dry-run by default; APPLY=1 writes. Needs FRONTEND_URL'
  task seed: :environment do
    apply = ENV['APPLY'] == '1'
    seeder = EmailCampaigns::TemplateLibrarySeeder.new(base_url: ENV.fetch('FRONTEND_URL', nil))
    report = apply ? seeder.apply! : seeder.plan

    puts(apply ? 'mode: apply' : 'mode: dry_run (nothing written; APPLY=1 writes)')
    { create: report.created, update: report.updated, unchanged: report.unchanged }.each do |action, entries|
      entries.each { |entry| puts "#{action}: #{entry.fetch('key')}" }
    end
    report.retired.each { |template| puts "retire: id=#{template.id} #{template.name}" }
    report.unknown.each { |template| puts "keep (global outside the catalog): id=#{template.id} #{template.name}" }
    puts "account templates: #{EmailCampaignTemplate.where.not(account_id: nil).count} (never touched)"
    puts "totals: create=#{report.created.size} update=#{report.updated.size} unchanged=#{report.unchanged.size} " \
         "retire=#{report.retired.size} unknown_kept=#{report.unknown.size}"
  end
end
