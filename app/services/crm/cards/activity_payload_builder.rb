class Crm::Cards::ActivityPayloadBuilder
  def initialize(account:, user:, account_user:, activities:)
    @account = account
    @user = user
    @account_user = account_user
    @activities = activities
  end

  STAGE_ID_KEYS = %w[from_stage_id to_stage_id target_stage_id stage_id].freeze
  # to_user_id: quem recebeu a reunião de quem saiu da conta (meeting_host_reassigned, #1188).
  OWNER_ID_KEYS = %w[owner_id assignee_id to_user_id].freeze
  CONTACT_ID_KEYS = %w[contact_id].freeze
  SENSITIVE_PAYLOAD_KEYS = %w[error send_error].freeze
  # Fase D: resolve o destino de time do handoff do agente nativo (assign_team)
  # para nome legível na timeline. Aditivo; nenhum event_type existente usa team_id.
  TEAM_ID_KEYS = %w[team_id].freeze

  def perform
    activities = visible_activities
    actor_names = actor_names_for(activities)
    @label_cache = build_label_cache(activities)

    activities.map { |activity| activity_payload(activity, actor_names) }
  end

  private

  def activity_payload(activity, actor_names)
    {
      id: activity.id,
      event_type: activity.event_type,
      actor_type: activity.actor_type,
      actor_id: activity.actor_id,
      actor_name: actor_names[activity.actor_id] || system_actor_name(activity),
      conversation_id: activity.conversation_id,
      payload: sanitized_activity_payload(activity.payload),
      labels: labels_for(activity),
      created_at: activity.created_at.iso8601
    }
  end

  # Builds a per-activity { payload_key => human_name } map so the frontend can
  # render friendly copy without exposing raw ids. Names are batched once across
  # the already visibility-filtered activity set to avoid N+1 lookups.
  def labels_for(activity)
    payload = activity.payload
    return {} unless payload.is_a?(Hash)

    payload.each_with_object({}) do |(key, value), labels|
      name = label_name_for(key.to_s, value)
      labels[key] = name if name.present?
    end
  end

  def label_name_for(key, value)
    return if value.blank?

    if STAGE_ID_KEYS.include?(key)
      @label_cache[:stages][value.to_i]
    elsif OWNER_ID_KEYS.include?(key)
      @label_cache[:users][value.to_i]
    elsif CONTACT_ID_KEYS.include?(key)
      @label_cache[:contacts][value.to_i]
    elsif TEAM_ID_KEYS.include?(key)
      @label_cache[:teams][value.to_i]
    end
  end

  def build_label_cache(activities)
    ids = collect_label_ids(activities)
    {
      stages: stage_names(ids[:stages]),
      users: user_names(ids[:users]),
      contacts: contact_names(ids[:contacts]),
      teams: team_names(ids[:teams])
    }
  end

  def collect_label_ids(activities)
    ids = { stages: [], users: [], contacts: [], teams: [] }
    activities.each do |activity|
      next unless activity.payload.is_a?(Hash)

      activity.payload.each do |key, value|
        next if value.blank?

        key = key.to_s
        ids[:stages] << value.to_i if STAGE_ID_KEYS.include?(key)
        ids[:users] << value.to_i if OWNER_ID_KEYS.include?(key)
        ids[:contacts] << value.to_i if CONTACT_ID_KEYS.include?(key)
        ids[:teams] << value.to_i if TEAM_ID_KEYS.include?(key)
      end
    end
    ids.transform_values { |list| list.uniq.reject(&:zero?) }
  end

  def stage_names(ids)
    return {} if ids.blank?

    @account.crm_pipeline_stages.where(id: ids).pluck(:id, :name).to_h
  end

  def user_names(ids)
    return {} if ids.blank?

    @account.users.where(id: ids).pluck(:id, :name).to_h
  end

  def contact_names(ids)
    return {} if ids.blank?

    @account.contacts.where(id: ids).pluck(:id, :name).to_h
  end

  def team_names(ids)
    return {} if ids.blank?

    @account.teams.where(id: ids).pluck(:id, :name).to_h
  end

  def visible_activities
    return @activities if administrator?

    @activities.reject { |activity| hidden_conversation_references?(activity) }
  end

  def hidden_conversation_references?(activity)
    activity_conversation_ids(activity).any? { |conversation_id| visible_conversation_ids.exclude?(conversation_id) }
  end

  def visible_conversation_ids
    @visible_conversation_ids ||= conversations.select { |_id, conversation| visibility.visible?(conversation) }.keys
  end

  def conversations
    @conversations ||= Conversation.where(account_id: @account.id, id: all_conversation_ids).index_by(&:id)
  end

  def all_conversation_ids
    @all_conversation_ids ||= @activities.flat_map { |activity| activity_conversation_ids(activity) }.uniq
  end

  def activity_conversation_ids(activity)
    ([activity.conversation_id] + payload_conversation_ids(activity.payload))
      .compact
      .map(&:to_i)
      .reject(&:zero?)
      .uniq
  end

  def payload_conversation_ids(payload)
    case payload
    when Hash
      payload.flat_map { |key, value| payload_conversation_ids_for_pair(key, value) }
    when Array
      payload.flat_map { |value| payload_conversation_ids(value) }
    else
      []
    end
  end

  def payload_conversation_ids_for_pair(key, value)
    return [value] if key.to_s == 'conversation_id'
    return [value['id'] || value[:id]] if key.to_s == 'source_conversation' && value.is_a?(Hash)

    payload_conversation_ids(value)
  end

  def sanitized_activity_payload(payload)
    sanitized = remove_sensitive_payload_fields(payload)
    return sanitized if administrator?

    remove_source_conversation(sanitized)
  end

  def remove_sensitive_payload_fields(payload)
    case payload
    when Hash
      payload.each_with_object({}) do |(key, value), sanitized|
        next if SENSITIVE_PAYLOAD_KEYS.include?(key.to_s)

        sanitized[key] = remove_sensitive_payload_fields(value)
      end
    when Array
      payload.map { |value| remove_sensitive_payload_fields(value) }
    else
      payload
    end
  end

  def remove_source_conversation(payload)
    case payload
    when Hash
      payload.each_with_object({}) do |(key, value), sanitized|
        next if key.to_s == 'source_conversation'

        sanitized[key] = remove_source_conversation(value)
      end
    when Array
      payload.map { |value| remove_source_conversation(value) }
    else
      payload
    end
  end

  def actor_names_for(activities)
    user_ids = activities.select { |activity| activity.actor_type == 'user' }.filter_map(&:actor_id).uniq
    @account.users.where(id: user_ids).pluck(:id, :name).to_h
  end

  def system_actor_name(activity)
    return 'Sistema' if activity.actor_type == 'system'

    nil
  end

  def visibility
    @visibility ||= Crm::Conversations::Visibility.new(account: @account, user: @user, account_user: @account_user)
  end

  def administrator?
    @account_user&.administrator?
  end
end
