module Autonomia::Agents::PublishContract
  private

  def publish_inboxes
    single_present, many_present = publish_selection_presence

    raise_publish_rejection('inbox_selection_conflict') if single_present && many_present
    return [] unless single_present || many_present

    return publish_single_inboxes if single_present

    publish_multiple_inboxes
  end

  def publish_selection_presence
    [
      params.key?(:inbox_id) || params.key?('inbox_id'),
      params.key?(:inbox_ids) || params.key?('inbox_ids')
    ]
  end

  def publish_single_inboxes
    id = publish_single_inbox_id
    return [] if id.blank?

    [current_account.inboxes.find(id)]
  end

  def publish_multiple_inboxes
    ids = publish_many_inbox_ids
    inboxes = current_account.inboxes.where(id: ids).order(:id).to_a
    raise ActiveRecord::RecordNotFound unless inboxes.length == ids.length

    inboxes
  end

  def reject_publish_fields!
    values = params[:agent]
    return unless values.respond_to?(:key?)

    forbidden = %i[name greeting].find { |field| values.key?(field) || values.key?(field.to_s) }
    return if forbidden.blank?

    raise ::Autonomia::Agents::Errors::PublishRejected.new(code: 'publish_field_not_allowed', key: forbidden.to_s)
  end

  def publish_single_inbox_id
    value = params[:inbox_id] || params['inbox_id']
    return if value.blank?

    value
  end

  def publish_many_inbox_ids
    value = params[:inbox_ids] || params['inbox_ids']
    valid = value.is_a?(Array) && value.all? { |id| id.is_a?(Integer) && id.positive? }
    valid &&= value.uniq.length == value.length
    raise_publish_rejection('inbox_selection_invalid') unless valid

    value
  end

  def raise_publish_rejection(code, key: nil)
    raise ::Autonomia::Agents::Errors::PublishRejected.new(code: code, key: key)
  end

  def publish_config
    values = params[:agent]
    return {} unless values.respond_to?(:key?)

    parameter_hash(values[:config] || values['config'])
  end
end
