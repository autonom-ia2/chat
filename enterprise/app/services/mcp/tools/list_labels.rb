class Mcp::Tools::ListLabels < Mcp::Tools::Base
  tool_name 'list_labels'
  description 'List the labels of the account. Only these labels can be put on conversations and contacts.'
  scope 'conversations:read'
  annotations(read_only_hint: true, destructive_hint: false, open_world_hint: false)
  input_schema(properties: {})

  def self.perform
    labels = Current.account.labels.order(:title)

    respond(labels: labels.map { |label| { title: label.title, description: label.description } })
  end
end
