class CampaignImports::ColumnProfiler
  PROFILE_SAMPLE_SIZE = 50
  EXAMPLE_COUNT = 3
  EXAMPLE_LENGTH = 80
  EXAMPLE_MASK = Hash.new('x').merge(
    ('a'..'z').index_with('a'), ('A'..'Z').index_with('A'),
    ('0'..'9').index_with('0'), ' +-().,/:;_'.each_char.to_h { |char| [char, char] }
  ).freeze

  # reveal_area_codes (customer_base reading, #1246): phones and emails go in the CampaignImports::JevMask
  # shape (country code, DDD and email domain visible) instead of all zeros and "[email address]".
  def initialize(rows, reveal_area_codes: false)
    @reveal_area_codes = reveal_area_codes
    @email_positions = Hash.new { |hash, index| hash[index] = [] }
    rows.each_with_index do |row, position|
      row.values.each_with_index { |value, index| @email_positions[index] << position if email_like?(value.to_s) }
    end
  end

  def profiles(column_count, rows, header_index)
    sample = profile_sample(rows)
    Array.new(column_count) do |index|
      values = profiled_values(sample, index)
      positions = @email_positions[index]
      valid_emails = positions.size - (positions.bsearch_index { |position| position > header_index } || positions.size)
      examples = examples_for(values, valid_emails)
      {
        sampled_rows: sample.size, total_rows: rows.size, total_valid_emails: valid_emails, non_blank_count: values.length,
        email_like_count: values.count { |value| email_like?(value) },
        examples: examples.first(EXAMPLE_COUNT)
      }
    end
  end

  private

  # With the area codes revealed the example already shows the email (domain only), so no marker is added.
  def examples_for(values, valid_emails)
    examples = values.uniq.first(EXAMPLE_COUNT).map { |value| example_value(value) }
    return examples if @reveal_area_codes || valid_emails.zero? || examples.include?('[email address]')

    ['[email address]', *examples]
  end

  def example_value(value)
    revealed = @reveal_area_codes && CampaignImports::JevMask.mask(value.first(EXAMPLE_LENGTH))
    return revealed if revealed
    return '[email address]' if email_like?(value)
    return '[malformed email address]' if value.include?('@')

    value.first(EXAMPLE_LENGTH).each_char.map { |char| EXAMPLE_MASK[char] }.join
  end

  def profile_sample(rows)
    return rows if rows.length <= PROFILE_SAMPLE_SIZE

    step = (rows.length - 1).fdiv(PROFILE_SAMPLE_SIZE - 1)
    Array.new(PROFILE_SAMPLE_SIZE) { |index| rows[(index * step).round] }.uniq
  end

  def profiled_values(rows, index)
    rows.filter_map do |row|
      value = row.values[index].to_s
      value.strip if profile_value?(value)
    end.reject(&:empty?)
  end

  def profile_value?(value)
    value.valid_encoding? && value.exclude?("\0")
  end

  def email_like?(value)
    return false unless profile_value?(value)

    EmailCampaigns::EmailNormalizer.normalize!(value)
    true
  rescue EmailCampaigns::EmailNormalizer::Error
    false
  end
end
