# Strips values that could identify a person or leak a secret before an error message
# reaches the logs: long token-like strings and long digit runs (phones, documents).
module CampaignImports::SafeLogMessage
  MAX_LENGTH = 300
  MIN_DIGIT_RUN = 6
  # Pattern prescribed by the secrets rule for redacting token-like values.
  TOKEN_PATTERN = /[A-Za-z0-9_\-]{32,}/

  def self.call(message)
    mask_digit_runs(message.to_s.gsub(TOKEN_PATTERN, '<REDACTED>')).truncate(MAX_LENGTH)
  end

  def self.mask_digit_runs(text)
    text.chars
        .chunk_while { |left, right| digit?(left) == digit?(right) }
        .map { |run| digit?(run.first) && run.size >= MIN_DIGIT_RUN ? '<DIGITS>' : run.join }
        .join
  end

  def self.digit?(char)
    char.between?('0', '9')
  end
end
