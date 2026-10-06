# Cuts the inner content of MJML ending tags (mj-text, mj-button...) and every comment out of an MJML
# string, leaving a token in their place, and puts them back later (#1074). That content is HTML/text
# for MJML, so it must never go through an XML parser: text, <br>, entities and Liquid stay byte for
# byte. Ending tags inside mj-attributes are left alone: there they are defaults (and, in corrupted
# heads, hold nested defaults that must be lifted). Plain string scanning — no regex.
class EmailCampaigns::MjmlEndingContent
  # Tags whose content is HTML/text for MJML, never MJML children.
  ENDING_TAGS = %w[mj-text mj-button mj-raw mj-table mj-navbar-link mj-social-element mj-accordion-title
                   mj-accordion-text mj-style mj-title mj-preview].freeze
  NAME_STOP = " \t\n\r/>".freeze
  # tag is nil for a comment.
  Slot = Struct.new(:tag, :content)

  attr_reader :slots, :nonce

  # Rewrites the content of the given ending tags without parsing the rest, so it works on any
  # MJML, well-formed or not.
  def self.map(mjml, tags)
    cut = new(mjml.to_s)
    cut.restore(cut.skeleton) { |slot| tags.include?(slot.tag) ? yield(slot.content) : slot.content }
  end

  def initialize(src)
    @src = src
    @nonce = SecureRandom.hex(6)
    @slots = []
    @out = +''
    @in_attributes = false
  end

  def skeleton
    @skeleton ||= scan
  end

  # Puts every slot back in `text` (the skeleton, or what was serialized from it).
  def restore(text)
    slots.each_with_index.reduce(text) do |acc, (slot, index)|
      content = block_given? ? yield(slot) : slot.content
      acc.sub(token(index)) { content }
    end
  end

  private

  def token(index)
    "MJSLOT#{nonce}N#{index}E"
  end

  def scan
    pos = 0
    while pos < @src.length
      lt = @src.index('<', pos)
      break if lt.nil?

      @out << @src[pos...lt]
      pos = @src[lt, 4] == '<!--' ? cut_comment(lt) : copy_tag(lt)
      return @out if pos.nil?
    end
    @out << @src[pos..].to_s
  end

  # Comments are cut out whole: XML would read entities and '--' inside them.
  def cut_comment(start)
    close = @src.index('-->', start)
    finish = close ? close + 3 : @src.length
    add_slot(nil, @src[start...finish])
    finish
  end

  def add_slot(tag, content)
    @slots << Slot.new(tag, content)
    @out << token(@slots.length - 1)
  end

  def copy_tag(start)
    tag_end = find_tag_end(start)
    if tag_end.nil?
      @out << @src[start..]
      return nil
    end

    tag = @src[start..tag_end]
    closing = @src[start + 1] == '/'
    name = read_tag_name(start + (closing ? 2 : 1))
    @out << tag
    @in_attributes = !closing && !self_closing?(tag) if name == 'mj-attributes'
    return cut_content(name, tag_end + 1) if cuttable?(name, closing, tag)

    tag_end + 1
  end

  def cuttable?(name, closing, tag)
    !closing && !@in_attributes && ENDING_TAGS.include?(name) && !self_closing?(tag)
  end

  def cut_content(name, from)
    close_at = @src.index("</#{name}", from)
    return from if close_at.nil?

    add_slot(name, @src[from...close_at])
    close_at
  end

  def read_tag_name(from)
    finish = from
    finish += 1 while finish < @src.length && NAME_STOP.exclude?(@src[finish])
    @src[from...finish]
  end

  # Index of the `>` closing the tag opened at `from`, skipping quoted attribute values.
  def find_tag_end(from)
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

  def self_closing?(tag)
    tag[0...-1].rstrip.end_with?('/')
  end
end
