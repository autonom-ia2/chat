module WhatsappApiCampaigns
  # Fills {{contact.name}}, {{contact.first_name}} and {{contact.company}} in a WhatsApp API message.
  # Read and filled in one left-to-right pass by CampaignJourney::TemplatePlaceholders (no regular
  # expressions, #999): inserted values are never scanned again.
  class TemplateRenderer
    # contact.company (#999, PRD §8.3 and D7): the name of the contact's company. A recipient
    # without one is skipped with "falta empresa" unless the campaign has a default text
    # (CampaignJourney::WhatsappApiAudience).
    COMPANY_VARIABLE = 'contact.company'.freeze
    SUPPORTED_VARIABLES = (%w[contact.name contact.first_name] + [COMPANY_VARIABLE]).freeze

    def self.variables_in(template)
      CampaignJourney::TemplatePlaceholders.keys(template)
    end

    def self.unsupported_variables_in(template)
      variables_in(template) - SUPPORTED_VARIABLES
    end

    # Same source as the journey's WhatsApp Oficial variables (CampaignJourney::VariableBindings).
    def self.company_name(contact)
      (contact.try(:company)&.name.presence || contact.additional_attributes.to_h['company_name']).to_s.squish.presence
    end

    def initialize(template:, contact:, variables: {})
      @template = template.to_s
      @contact = contact
      @variables = (variables || {}).transform_keys(&:to_s)
    end

    def render
      keys = CampaignJourney::TemplatePlaceholders.keys(@template)
      CampaignJourney::TemplatePlaceholders.render(@template, keys.index_with { |key| value_for(key) })
    end

    private

    def value_for(variable)
      case variable
      when 'contact.name'
        @contact.name.to_s
      when 'contact.first_name'
        @contact.name.to_s.split.first.to_s
      when COMPANY_VARIABLE
        self.class.company_name(@contact) || @variables.fetch(COMPANY_VARIABLE, '')
      else
        # Supplemental named variables (e.g. AI-composed values keyed by slot).
        # Positional {{1}}/{{2}} placeholders remain unsupported in pre-approved
        # templates, so anything not provided falls back to an empty string.
        @variables.fetch(variable, '')
      end
    end
  end
end
