# Text the model writes for the person to read (#1095: what changed, why it cannot be done), kept short for the
# editor: one line, at most `max` characters, cut at the end of a sentence when there is one in the second half,
# otherwise at a word with an ellipsis. Plain string methods — no regex.
module EmailCampaigns::Ai::ShortSentence
  module_function

  SENTENCE_ENDS = ['.', '!', '?'].freeze
  ELLIPSIS = '…'.freeze

  def call(text, max)
    line = text.to_s.split.join(' ')
    return line if line.length <= max

    cut = line.first(max)
    sentence_end = SENTENCE_ENDS.filter_map { |mark| cut.rindex(mark) }.max
    return cut[0..sentence_end] if sentence_end && sentence_end >= (max / 2)

    word_end = cut.rindex(' ') || (max - 1)
    "#{cut[0...word_end].rstrip.first(max - 1)}#{ELLIPSIS}"
  end
end
