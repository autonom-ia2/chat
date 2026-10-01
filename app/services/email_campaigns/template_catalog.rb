# The original licensed designs remain intact. Seeded bodies share the builder
# sanitizer. HTML assets are compiled before release, including the protected footer.
class EmailCampaigns::TemplateCatalog
  ROOT = Rails.root.join('db/seeds/email_templates').freeze
  NAME_KEYS = %w[firstName first_name user_name recipient_name].freeze

  def self.entries
    @entries ||= JSON.parse(ROOT.join('catalog.json').read).freeze
  end

  def self.key_for(template)
    return if template.account_id

    entries.find { |entry| entry.fetch('name') == template.name }&.fetch('key')
  end

  def self.body(entry)
    source = ROOT.join(entry.fetch('path')).read
    # Design-author notes are not campaign content or personalization fields.
    source = source.split('<!--').map.with_index { |part, index| index.zero? ? part : part.split('-->', 2).last }.join
    source = NAME_KEYS.reduce(source) do |body, key|
      body.gsub("{{#{key}}}", '{{ nome }}').gsub("{{ #{key} }}", '{{ nome }}')
    end
    EmailCampaigns::Ai::Sanitizer.new(source).perform
  end
end
