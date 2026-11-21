class Mcp::Tools::ListCannedResponses < Mcp::Tools::Base
  tool_name 'list_canned_responses'
  description 'List the canned responses (ready answers) of the account. Pass search to find the ones whose short code or text contains it.'
  scope 'conversations:read'
  annotations(read_only_hint: true, destructive_hint: false, open_world_hint: false)
  input_schema(properties: { search: { type: 'string', description: 'Text to look for in the short code or the content.' } })

  def self.perform(search: nil)
    responses = Current.account.canned_responses.order(:short_code)
    if search.present?
      responses = responses.where('short_code ILIKE :search OR content ILIKE :search', search: "%#{CannedResponse.sanitize_sql_like(search.strip)}%")
    end

    respond(canned_responses: responses.limit(100).map { |response| { short_code: response.short_code, content: response.content } })
  end
end
