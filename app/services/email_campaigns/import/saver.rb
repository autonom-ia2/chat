# Saves a finished import as a template of the account in "Meus modelos" (#1099, delivery B). The design is the copy
# the server produced and kept — the browser only sends the name — and it is checked again (SaveCheck) right before
# saving, inside a row lock so two clicks cannot save it twice. Raises Blocked with what still has to be solved.
class EmailCampaigns::Import::Saver
  CATEGORY = 'meus-modelos'.freeze

  class Blocked < StandardError
    attr_reader :code, :problems

    def initialize(code, problems = [])
      @code = code
      @problems = problems
      super("email template import not saved: #{code}")
    end
  end

  def self.call(import, name:)
    new(import, name).call
  end

  def initialize(import, name)
    @import = import
    @name = name.to_s.strip
  end

  def call
    raise Blocked, :name_required if @name.empty?

    @import.with_lock do
      raise Blocked, :not_ready unless @import.status == 'ready'

      problems = EmailCampaigns::Import::SaveCheck.call(@import.result_mjml, @import)
      raise Blocked.new(:blocked, problems) if problems.any?

      template = create_template
      @import.update!(status: 'saved', email_campaign_template: template)
      template
    end
  end

  private

  def create_template
    template = EmailCampaignTemplate.new(account: @import.account, name: @name, category: CATEGORY,
                                         body_mjml: EmailCampaigns::LockedFooter.ensure(@import.result_mjml))
    if template.invalid?
      raise Blocked, :name_taken if template.errors.of_kind?(:name, :taken)

      raise Blocked, template.errors.include?(:name) ? :name_invalid : :invalid
    end

    template.save!
    template
  end
end
