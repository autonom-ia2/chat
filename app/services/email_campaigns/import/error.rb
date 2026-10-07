# Why an import could not even start (#1099). The screen turns the code into one sentence with one way out; the
# message never carries any of the client's markup.
class EmailCampaigns::Import::Error < StandardError
  CODES = %i[too_large empty too_many_nodes too_deep malformed_mjml invalid_source_kind].freeze

  attr_reader :code

  def initialize(code)
    raise ArgumentError, "unknown import error #{code}" unless CODES.include?(code)

    @code = code
    super("email template import refused: #{code}")
  end
end
