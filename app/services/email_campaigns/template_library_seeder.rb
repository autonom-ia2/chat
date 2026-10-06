# Publishes the shared gallery library (EmailCampaigns::TemplateCatalog) into email_campaign_templates (#1082).
# Global rows only (account_id IS NULL): creates or updates the catalog designs, deletes the globals listed in
# retired.json and reports (keeps) any other global. Account templates ("Meus modelos") are never read for
# writing. #plan writes nothing; #apply! writes everything in one transaction or nothing.
class EmailCampaigns::TemplateLibrarySeeder
  Report = Struct.new(:created, :updated, :unchanged, :retired, :unknown, keyword_init: true)

  def initialize(base_url:)
    @base_url = base_url
  end

  def plan
    report_for(prepared)
  end

  def apply!
    designs = prepared
    EmailCampaignTemplate.transaction do
      report_for(designs).tap do |report|
        (report.created + report.updated).each { |entry| write(entry, designs.fetch(entry)) }
        report.retired.each(&:destroy!)
      end
    end
  end

  private

  def catalog
    EmailCampaigns::TemplateCatalog
  end

  # Every design is rendered and checked before any write: never publish a partial library.
  def prepared
    catalog.entries.to_h do |entry|
      mjml, html = catalog.published(entry, base_url: @base_url)
      raise "Template without protected footer: #{entry.fetch('key')}" unless [mjml, html].all? { |markup| footer?(markup) }

      [entry, { body_mjml: mjml, body_html: html, category: entry.fetch('category') }]
    end
  end

  def footer?(markup)
    markup.include?('footer-locked') && markup.include?('{{ unsubscribe_url }}')
  end

  def report_for(designs)
    globals = EmailCampaignTemplate.global.order(:id).to_a
    by_name = globals.index_by(&:name)
    groups = designs.keys.group_by { |entry| status(by_name[entry.fetch('name')], designs.fetch(entry)) }
    retired, others = globals.partition { |template| catalog.retired_names.include?(template.name) }
    Report.new(created: groups.fetch(:create, []), updated: groups.fetch(:update, []), unchanged: groups.fetch(:unchanged, []),
               retired: retired, unknown: others.reject { |template| catalog_names.include?(template.name) })
  end

  def catalog_names
    @catalog_names ||= catalog.entries.map { |entry| entry.fetch('name') }
  end

  def status(existing, attributes)
    return :create if existing.nil?

    attributes.all? { |field, value| existing.public_send(field) == value } ? :unchanged : :update
  end

  def write(entry, attributes)
    EmailCampaignTemplate.find_or_initialize_by(account_id: nil, name: entry.fetch('name')).update!(attributes)
  end
end
