# A tool runs as the user who connected the app, on the account the token is bound to.
# The OAuth scope limits what the app may do. The policies still decide what the user may do.
class Mcp::Tools::Base < MCP::Tool
  NOT_FOUND_MESSAGE = 'Not found, or you do not have access to it.'.freeze

  class << self
    attr_reader :required_scope

    def scope(value)
      @required_scope = value
    end

    # ChatGPT reads securitySchemes to know which scope to ask the user for.
    def to_h
      super.merge(securitySchemes: [{ type: 'oauth2', scopes: [required_scope] }])
    end

    def call(server_context:, **arguments)
      return insufficient_scope_response(server_context[:base_url]) unless server_context[:scopes].include?(required_scope)

      perform(**arguments)
    rescue ActiveRecord::RecordNotFound, Pundit::NotAuthorizedError
      error_response(NOT_FOUND_MESSAGE)
    rescue ActiveRecord::RecordInvalid => e
      error_response(e.message)
    end

    private

    def respond(data)
      MCP::Tool::Response.new([{ type: 'text', text: data.to_json }], structured_content: data)
    end

    def error_response(message, meta: nil)
      MCP::Tool::Response.new([{ type: 'text', text: message }], error: true, meta: meta)
    end

    # The challenge in _meta makes the client ask the user for the missing scope.
    def insufficient_scope_response(base_url)
      description = "This action needs the #{required_scope} scope"
      challenge = Mcp::BearerChallenge.build(base_url: base_url, error: 'insufficient_scope', error_description: description)

      error_response(description, meta: { 'mcp/www_authenticate' => [challenge] })
    end

    def authorize(record, query)
      Pundit.authorize({ user: Current.user, account: Current.account, account_user: Current.account_user }, record, query)
    end

    def find_conversation(display_id)
      Current.account.conversations.find_by!(display_id: display_id).tap { |conversation| authorize(conversation, :show?) }
    end

    def contact_summary(contact)
      {
        id: contact.id,
        name: contact.name,
        email: contact.email,
        phone_number: contact.phone_number,
        identifier: contact.identifier,
        company: contact.additional_attributes&.dig('company_name'),
        created_at: contact.created_at.iso8601,
        last_activity_at: contact.last_activity_at&.iso8601
      }
    end

    def find_contact(contact_id)
      Current.account.contacts.find(contact_id).tap { |contact| authorize(contact, :show?) }
    end

    # A model may invent a label. Saving it would create a tag that no label in the account matches.
    def unknown_labels_error(labels)
      account_labels = Current.account.labels.pluck(:title)
      unknown = labels.to_a - account_labels
      error_response("Unknown labels: #{unknown.join(', ')}. Labels of the account: #{account_labels.join(', ')}") if unknown.any?
    end

    def conversation_summary(conversation)
      {
        id: conversation.display_id,
        status: conversation.status,
        priority: conversation.priority,
        inbox: conversation.inbox.name,
        contact: conversation.contact.name,
        assignee: conversation.assignee&.name,
        team: conversation.team&.name,
        labels: conversation.cached_label_list_array,
        created_at: conversation.created_at.iso8601,
        last_activity_at: conversation.last_activity_at.iso8601
      }
    end
  end
end
