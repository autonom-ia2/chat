# Finds the top-level elements inside <mj-body> of a MjmlEndingContent skeleton (only tags remain; text and
# comments are tokens), for EmailCampaigns::Ai::MjmlSections (#1095). Returns [prefix, [block...], suffix],
# or nil when there is no body or the tags do not balance. Plain string scanning — no regex.
class EmailCampaigns::Ai::MjmlSections::Scanner
  BODY_OPEN = '<mj-body'.freeze
  BODY_CLOSE = '</mj-body>'.freeze

  def initialize(skeleton)
    @src = skeleton
  end

  def call
    open_at = @src.index(BODY_OPEN)
    close_at = @src.rindex(BODY_CLOSE)
    return nil if open_at.nil? || close_at.nil?

    body_start = tag_end(open_at)
    return nil if body_start.nil? || body_start >= close_at

    blocks = top_level_blocks(body_start + 1, close_at)
    blocks && [@src[0..body_start], blocks, @src[close_at..]]
  end

  private

  def top_level_blocks(from, limit)
    blocks = []
    depth = 0
    start = nil
    pos = from
    while (open_at = @src.index('<', pos)) && open_at < limit
      finish = tag_end(open_at)
      return nil if finish.nil? || finish >= limit

      depth, start = step(open_at, finish, depth, start, blocks)
      return nil if depth.negative?

      pos = finish + 1
    end
    depth.zero? ? blocks : nil
  end

  # One tag: opens, closes or (self-closed) both. Collects a block when depth goes back to zero.
  def step(open_at, finish, depth, start, blocks)
    if @src[open_at + 1] == '/'
      depth -= 1
      blocks << @src[start..finish] if depth.zero? && start
    elsif @src[finish - 1] == '/'
      blocks << @src[open_at..finish] if depth.zero?
    else
      start = open_at if depth.zero?
      depth += 1
    end
    [depth, start]
  end

  # Index of the `>` closing the tag opened at `from`, skipping quoted attribute values.
  def tag_end(from)
    quote = nil
    (from...@src.length).each do |i|
      char = @src[i]
      if quote
        quote = nil if char == quote
      elsif ['"', "'"].include?(char)
        quote = char
      elsif char == '>'
        return i
      end
    end
    nil
  end
end
