class Instagram::Testers::ResponseParser
  PREFIX = 'for (;;);'.freeze
  ROLE = 'instagram testers'.freeze
  STATUSES = { 'PENDING' => 'pending', 'CONFIRMED' => 'accepted' }.freeze

  def self.parse(body, error_code:)
    raise Instagram::Testers::Error, error_code unless body.is_a?(String) && body.bytesize <= 2.megabytes

    document = JSON.parse(body.strip.delete_prefix(PREFIX))
    raise Instagram::Testers::Error, error_code unless clean_document?(document)

    document
  rescue JSON::ParserError
    raise Instagram::Testers::Error.new(error_code), cause: nil
  end

  def self.candidates(document)
    entries = document.dig('payload', 'entries') if document['payload'].is_a?(Hash)
    raise Instagram::Testers::Error, 'meta_unavailable' unless entries.is_a?(Array) && entries.length <= 100

    results = entries.map { |entry| candidate(entry) }
    raise Instagram::Testers::Error, 'meta_unavailable' unless results.pluck(:id).uniq.length == results.length

    results
  end

  def self.status(document, target_id)
    roles_container = roles_container(document)
    entries = valid_roles(roles_container).flat_map { |group| group_testers(group) }
    by_id = entries.group_by { |entry| entry.fetch('id') }
    statuses = by_id.transform_values { |users| users.pluck('status').uniq }
    raise Instagram::Testers::Error, 'unknown_status' if statuses.values.any? { |values| values.length > 1 }

    STATUSES.fetch(statuses.fetch(target_id, []).first, 'absent')
  end

  def self.valid_roles(container)
    roles = container['app_roles']
    raise Instagram::Testers::Error, 'unknown_status' unless roles.is_a?(Array) && complete?(container)

    roles
  end

  def self.roles_container(document)
    data = document['data']
    container = data['get_app_roles'] if data.is_a?(Hash)
    raise Instagram::Testers::Error, 'unknown_status' unless container.is_a?(Hash)

    container
  end

  def self.clean_document?(document)
    document.is_a?(Hash) && clean_errors?(document)
  end

  def self.clean_errors?(value)
    case value
    when Hash
      no_errors?(value) && value.values.all? { |item| clean_errors?(item) }
    when Array
      value.all? { |item| clean_errors?(item) }
    else
      true
    end
  end

  def self.no_errors?(value)
    value['error'].nil? && (value['errors'].nil? || value['errors'] == [])
  end

  def self.candidate(entry)
    valid = entry.is_a?(Hash) && Instagram::Testers::Validation.id?(entry['uniqueID']) &&
            Instagram::Testers::Validation.username?(entry['text']) && valid_name?(entry['subtitle']) &&
            Instagram::Testers::Validation.avatar?(entry['photo'])
    raise Instagram::Testers::Error, 'meta_unavailable' unless valid

    { id: entry['uniqueID'], username: Instagram::Testers::Validation.normalize_username(entry['text']),
      name: entry['subtitle'], avatar_url: entry['photo'] }
  end

  def self.valid_name?(name)
    name.is_a?(String) && name.length <= 500
  end

  def self.group_testers(group)
    raise Instagram::Testers::Error, 'unknown_status' unless valid_group?(group)
    return [] unless group['role'] == ROLE

    group['users'].each do |user|
      raise Instagram::Testers::Error, 'unknown_status' unless valid_tester?(user)
    end
  end

  def self.valid_group?(group)
    group.is_a?(Hash) && group['role'].is_a?(String) && group['users'].is_a?(Array) && complete?(group)
  end

  def self.valid_tester?(user)
    user.is_a?(Hash) && Instagram::Testers::Validation.id?(user['id']) && STATUSES.key?(user['status'])
  end

  def self.complete?(container)
    return true unless container.key?('page_info')

    page = container['page_info']
    page.is_a?(Hash) && page['has_next_page'] == false
  end

  private_class_method :complete?, :clean_document?, :clean_errors?, :candidate, :valid_name?, :group_testers,
                       :roles_container, :valid_roles, :no_errors?, :valid_tester?, :valid_group?
end
