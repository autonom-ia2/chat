# Why an import could not even start, or could not finish (#1099). The screen turns the code into one sentence with one
# way out; the message never carries any of the client's markup. The engine's own codes come first; the others belong
# to the import flow (delivery B): the received file, the address, the job; the last ones to the fixes the screen asks
# for (delivery C).
class EmailCampaigns::Import::Error < StandardError
  ENGINE_CODES = %i[too_large empty too_many_nodes too_deep too_slow malformed_mjml invalid_source_kind].freeze
  FLOW_CODES = %i[unsupported_file zip_invalid zip_too_large zip_too_many_files zip_unsafe_path zip_no_html url_invalid
                  url_not_https url_unsafe url_unreachable url_not_html in_progress stalled configuration internal].freeze
  FIX_CODES = %i[not_ready fix_invalid fix_gone image_unfit image_too_large text_invalid].freeze
  CODES = (ENGINE_CODES + FLOW_CODES + FIX_CODES).freeze

  attr_reader :code

  def initialize(code)
    raise ArgumentError, "unknown import error #{code}" unless CODES.include?(code)

    @code = code
    super("email template import refused: #{code}")
  end
end
