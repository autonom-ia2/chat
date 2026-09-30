class Relationships::MediaQuery
  attr_reader :page, :per_page

  def initialize(record, user, filters)
    @record = record
    @account = record.account
    @user = user
    @filters = filters
    unknown = filters.keys - %w[q contact_id type from to group page per_page]
    raise Relationships::Configuration::Invalid, 'Filters must be strings' unless filters.values.all?(String)
    raise Relationships::Configuration::Invalid, 'Unknown media filters' if unknown.any?

    @page = integer_filter('page', 1)
    @per_page = integer_filter('per_page', 25)
    raise Relationships::Configuration::Invalid, 'Page size must be 5, 25 or 50' unless [5, 25, 50].include?(@per_page)
    raise Relationships::Configuration::Invalid, 'Invalid grouping' unless [nil, '', 'contact'].include?(filters['group'])
  end

  def authorized_messages
    conversations = @account.conversations.where(contact_id: relationship_contacts.select(:id))
    conversations = Conversations::PermissionFilterService.new(conversations, @user, @account).perform
    @account.messages.where(conversation_id: conversations.select(:id))
  end

  def scope
    relation = Attachment.where(account_id: @account.id).joins(:message, file_attachment: :blob).where(message_id: authorized_messages.select(:id))
    relation = filter_contact(relation)
    relation = filter_type(relation)
    relation = filter_period(relation)
    filter_name(relation)
  end

  def results
    relation = scope
    # The conversation contact is the relationship owner; outgoing message.contact_id can be nil.
    if @filters['group'] == 'contact'
      relation = relation.reorder('conversations.contact_id ASC', 'attachments.created_at DESC',
                                  'attachments.id DESC')
    end
    relation = relation.joins(message: :conversation) if @filters['group'] == 'contact'
    relation.order('attachments.created_at DESC', 'attachments.id DESC').offset((page - 1) * per_page).limit(per_page)
            .preload(file_attachment: :blob, message: [:sender, { conversation: :contact }])
  end

  private

  def relationship_contacts
    return @account.contacts.where(id: @record.id) if @record.is_a?(Contact)

    @record.contacts.where(account_id: @account.id)
  end

  def integer_filter(name, default)
    value = @filters.fetch(name, default.to_s)
    raise Relationships::Configuration::Invalid, "Invalid #{name}" unless value.is_a?(String) && !value.empty? && value.each_char.all? do |char|
      ('0'..'9').cover?(char)
    end && value.to_i.positive? && value.to_i.to_s == value

    value.to_i
  end

  def filter_contact(relation)
    return relation if @filters['contact_id'].blank?

    id = integer_filter('contact_id', nil)
    relation.where(messages: { conversation_id: @account.conversations.where(contact_id: id).select(:id) })
  end

  def filter_type(relation)
    return relation if @filters['type'].blank?
    raise Relationships::Configuration::Invalid, 'Invalid media type' unless %w[image audio video file].include?(@filters['type'])

    relation.where(file_type: @filters['type'])
  end

  def filter_name(relation)
    return relation if @filters['q'].blank?
    raise Relationships::Configuration::Invalid, 'Invalid filename query' if @filters['q'].length > 200

    relation.where('active_storage_blobs.filename ILIKE ?', "%#{ActiveRecord::Base.sanitize_sql_like(@filters['q'])}%")
  end

  def period_dates
    dates = %w[from to].map { |key| parse_date(@filters[key]) }
    raise Relationships::Configuration::Invalid, 'Invalid date range' if dates.all? && dates.first > dates.last

    dates
  end

  def parse_date(value)
    return if value.blank?

    date = Date.iso8601(value)
    raise Relationships::Configuration::Invalid, 'Expected date-only period' unless date.iso8601 == value

    date
  rescue Date::Error
    raise Relationships::Configuration::Invalid, 'Invalid calendar date'
  end

  def midnight(date)
    timezone = ActiveSupport::TimeZone[@account.reporting_timezone.presence || 'UTC']
    timezone.local(date.year, date.month, date.day)
  end

  def filter_period(relation)
    from, to = period_dates
    relation = relation.where('attachments.created_at >= ?', midnight(from)) if from
    relation = relation.where('attachments.created_at < ?', midnight(to + 1)) if to
    relation
  end
end
