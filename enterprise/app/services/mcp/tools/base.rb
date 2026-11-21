# A tool runs as the user who connected the app, on one of the accounts they administer (#3106): the one the call
# names in account_id, or the one chosen on the consent screen.
# The OAuth scope limits what the app may do. The policies still decide what the user may do.
class Mcp::Tools::Base < MCP::Tool
  NOT_FOUND_MESSAGE = 'Not found, or you do not have access to it.'.freeze
  ACCOUNT_ID_PROPERTY = {
    account_id: {
      type: 'integer',
      description: 'The account to act on, from list_accounts. Leave it out to use the account chosen when the app was connected.'
    }
  }.freeze
  NO_ACCOUNT_MESSAGE = 'You do not administer this account, or it is not active. Call list_accounts to see the accounts you can use.'.freeze

  class << self
    attr_reader :required_scope

    def scope(value)
      @required_scope = value
    end

    # Every tool takes the account it acts on.
    def input_schema(*args)
      value = args.first
      return super unless value.is_a?(Hash)

      super(value.merge(properties: ACCOUNT_ID_PROPERTY.merge(value[:properties] || {})))
    end

    # ChatGPT reads securitySchemes to know which scope to ask the user for.
    def to_h
      super.merge(securitySchemes: [{ type: 'oauth2', scopes: [required_scope] }])
    end

    def call(server_context:, account_id: nil, **arguments)
      return insufficient_scope_response(server_context[:base_url]) unless server_context[:scopes].include?(required_scope)

      account_user = Mcp::AccountAccess.new(Current.user).find(account_id || server_context[:default_account_id])
      return error_response(NO_ACCOUNT_MESSAGE) unless account_user

      on_account(account_user) { perform(**arguments) }
    rescue ActiveRecord::RecordNotFound, Pundit::NotAuthorizedError
      error_response(NOT_FOUND_MESSAGE)
    rescue ActiveRecord::RecordInvalid => e
      error_response(e.message)
    end

    private

    def on_account(account_user)
      previous = [Current.account, Current.account_user]
      Current.account = account_user.account
      Current.account_user = account_user
      yield
    ensure
      Current.account, Current.account_user = previous
    end

    def text_response(text, error: false)
      MCP::Tool::Response.new([{ type: 'text', text: text }], error: error)
    end

    # The Guide's engine for the platform_* tools (#3106): reads and actions go through the endpoint the screen calls.
    def consulta
      Autonomia::Guide::Consulta.new(account: Current.account, user: Current.user, account_user: Current.account_user)
    end

    def contexto
      Mcp::Plataforma::Contexto.new(app_name: Mcp::Request.app_name, account: Current.account, user: Current.user,
                                    account_user: Current.account_user)
    end

    def acoes
      contexto.acoes
    end

    def outside_catalog(action)
      neighbours = Autonomia::Guide::Rotas.vizinhas(acoes.catalogo, action)
      hint = neighbours.any? ? " For this, the platform has: #{neighbours.join(', ')}." : ''
      "\"#{action}\" is not a platform action. Use platform_catalog with kind write.#{hint}"
    end

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
