module WhatsappApiCampaigns
  class TemplateRenderer
    # contact.company (#999, PRD §8.3 and D7): the name of the contact's company. A recipient
    # without one is skipped with "falta empresa" unless the campaign has a default text
    # (CampaignJourney::WhatsappApiAudience).
    COMPANY_VARIABLE = 'contact.company'.freeze
    SUPPORTED_VARIABLES = (%w[contact.name contact.first_name] + [COMPANY_VARIABLE]).freeze
    VARIABLE_PATTERN = /\{\{\s*([^}]+?)\s*\}\}/.freeze

    def self.variables_in(template)
      template.to_s.scan(VARIABLE_PATTERN).flatten.map(&:strip).uniq
    end

    def self.unsupported_variables_in(template)
      variables_in(template) - SUPPORTED_VARIABLES
    end

    # Same source as the journey's WhatsApp Oficial variables (CampaignJourney::VariableBindings).
    def self.company_name(contact)
      contact.try(:company)&.name.presence || contact.additional_attributes.to_h['company_name'].presence
    end

    def initialize(template:, contact:, variables: {})
      @template = template.to_s
      @contact = contact
      @variables = (variables || {}).transform_keys(&:to_s)
    end

    def render
      @template.gsub(VARIABLE_PATTERN) do
        value_for(Regexp.last_match(1).strip)
      end
    end

    private

    def value_for(variable)
      case variable
      when 'contact.name'
        @contact.name.to_s
      when 'contact.first_name'
        @contact.name.to_s.split(/\s+/).first.to_s
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
