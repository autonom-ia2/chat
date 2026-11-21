# Does anything the user can do in the account, through the endpoint the screen calls (#3106).
# What can be undone runs at once and stays undoable for 5 days, like the Guide's. What cannot (a message or campaign
# that leaves the platform, a credential, a bulk job, deleting an inbox or a team) runs only when the call says the
# user confirmed it: the app asks the user first. Every action goes to the account's audit log with the app's name.
class Mcp::Tools::PlatformAction < Mcp::Tools::Base
  MAX_CHARACTERS = 4_000

  tool_name 'platform_action'
  description 'Do anything the user can do in the account (create, change, delete), with the user\'s permissions, through ' \
              'the same endpoint the screen uses. Get the action from platform_catalog and the body from platform_action_format. ' \
              'Ids come from what platform_read or an earlier step returned, never guessed. Most actions can be undone by the ' \
              'user for 5 days. Actions that cannot be undone (messages or campaigns to customers, credentials, bulk jobs, ' \
              'deleting an inbox or a team) need confirmed: true, which you send only after the user said yes to exactly that. ' \
              'Call once per step: the answer brings what the platform returned, including the id of what was created.'
  scope 'platform:write'
  annotations(read_only_hint: false, destructive_hint: true, open_world_hint: true)
  input_schema(
    properties: {
      action: { type: 'string', description: 'An action from platform_catalog, like "POST crm/pipelines" or "PATCH inboxes/:id".' },
      description: { type: 'string', description: 'One short sentence, in the user\'s language, saying what this step does. ' \
                                                  'It goes to the audit log. Never soften it: deleting is deleting.' },
      path: { type: 'object', description: 'Fills the ":id" parts of the action, like {"id": "12"}.' },
      body: { type: 'object', description: 'The fields to save, built from platform_action_format, with only values the user gave.' },
      confirmed: { type: 'boolean', description: 'true only when the user confirmed this exact action. Needed only for ' \
                                                 'actions that cannot be undone.' }
    },
    required: %w[action description]
  )

  def self.perform(action:, description:, path: {}, body: {}, confirmed: false)
    action = action.to_s.strip
    data = { caminho: path.to_h.deep_symbolize_keys, corpo: body.to_h.deep_symbolize_keys, descricao: description.to_s }
    return error_response(outside_catalog(action)) unless acoes.catalogo.include?(action)

    undoable = acoes.desfazivel?(action, data)
    return error_response(needs_confirmation(action)) unless undoable || confirmed == true

    done(undoable ? contexto.executar(action, data) : acoes.executar(action, data))
  rescue Autonomia::Guide::Acoes::Recusada => e
    error_response(e.message)
  end

  def self.done(result)
    return error_response([result.mensagem, result.dica].compact.join(' ')) unless result.ok

    answer = Autonomia::Guide::Resumo.new(corpo: result.corpo.to_s, teto: MAX_CHARACTERS).texto
    text_response(["Done. The platform answered: #{answer}", (" Note: #{result.aviso}" if result.aviso)].join)
  end

  def self.needs_confirmation(action)
    "\"#{action}\" cannot be undone. Tell the user exactly what will happen, and call again with confirmed: true " \
      'only after they say yes.'
  end
  private_class_method :done, :needs_confirmation
end
