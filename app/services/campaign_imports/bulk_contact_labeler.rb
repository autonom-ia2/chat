# Applies campaign import labels to many contacts with one query per block instead of a
# label_list save per contact. Saving through acts_as_taggable_on checks every tagging
# against all taggings of the same tag, so a base where every contact shares the same
# label became quadratic (6.000 rows took 189s). Taggings that already exist are skipped
# and the tag counters are kept in step.
class CampaignImports::BulkContactLabeler
  CONTEXT = 'labels'.freeze

  # contact_labels: [[contact_id, [label_title, ...]], ...]
  def initialize(contact_labels)
    @contact_labels = contact_labels
  end

  def perform
    return if contact_labels.empty?

    rows = missing_taggings
    return if rows.empty?

    ActsAsTaggableOn::Tagging.insert_all!(rows) # rubocop:disable Rails/SkipsModelValidations -- uniqueness checked in bulk above
    rows.group_by { |row| row[:tag_id] }.each do |tag_id, tag_rows|
      ActsAsTaggableOn::Tag.update_counters(tag_id, taggings_count: tag_rows.size) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  private

  attr_reader :contact_labels

  def missing_taggings
    wanted = contact_labels.flat_map { |contact_id, titles| titles.map { |title| [tags.fetch(title.downcase).id, contact_id] } }.uniq
    existing = ActsAsTaggableOn::Tagging.where(
      taggable_type: 'Contact', context: CONTEXT, taggable_id: contact_labels.map(&:first), tag_id: wanted.map(&:first).uniq
    ).pluck(:tag_id, :taggable_id).to_set
    now = Time.current
    wanted.reject { |pair| existing.include?(pair) }.map do |tag_id, contact_id|
      { tag_id: tag_id, taggable_type: 'Contact', taggable_id: contact_id, context: CONTEXT, created_at: now }
    end
  end

  def tags
    @tags ||= ActsAsTaggableOn::Tag.find_or_create_all_with_like_by_name(contact_labels.flat_map(&:last).uniq)
                                   .index_by { |tag| tag.name.downcase }
  end
end
